/* oxplayer tdweb media stream service worker */
self.addEventListener('install', function (event) {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});

var streamLogKey = '[OX_TG_WEB_STREAM]';
var servedMoovTokens = {};
// Browser media elements often don't decode until a 206 response completes.
// Keep each response small and let the player request the next byte range.
var responseChunkBytes = 2 * 1024 * 1024;
var readChunkBytes = 512 * 1024;

function streamLog(message) {
  console.info(streamLogKey + ' sw ' + message);
}

function parseRange(rangeHeader, size) {
  if (!rangeHeader || !rangeHeader.startsWith('bytes=')) {
    return { start: 0, end: size - 1, partial: false, openEnded: false, suffix: false };
  }
  var spec = rangeHeader.slice('bytes='.length).split(',')[0].trim();
  var dash = spec.indexOf('-');
  if (dash < 0) return { start: 0, end: size - 1, partial: false, openEnded: false, suffix: false };
  var a = spec.slice(0, dash).trim();
  var b = spec.slice(dash + 1).trim();
  var start;
  var end;
  var isSuffix = false;
  if (a === '') {
    var suffixLen = Number(b || 0);
    start = Math.max(0, size - suffixLen);
    end = size - 1;
    isSuffix = true;
  } else {
    start = Number(a);
    end = b === '' ? size - 1 : Number(b);
  }
  if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end < start) {
    return null;
  }
  end = Math.min(end, size - 1);
  return { start: start, end: end, partial: true, openEnded: b === '', suffix: isSuffix };
}

function askClient(client, message, transfer) {
  return new Promise(function (resolve, reject) {
    var channel = new MessageChannel();
    var timeout = setTimeout(function () {
      reject(new Error('tdweb stream client timeout'));
    }, 30000);
    channel.port1.onmessage = function (event) {
      clearTimeout(timeout);
      var data = event.data || {};
      if (data.ok) {
        resolve(data);
      } else {
        reject(new Error(data.error || 'tdweb stream client failed'));
      }
    };
    client.postMessage(message, transfer ? transfer.concat([channel.port2]) : [channel.port2]);
  });
}

self.addEventListener('fetch', function (event) {
  var url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  var streamIdx = url.pathname.indexOf('__ox_tdweb_stream');
  if (streamIdx < 0) return;

  event.respondWith((async function () {
    var parts = url.pathname.split('/');
    var tokenIdx = parts.indexOf('__ox_tdweb_stream') + 1;
    var token = parts[tokenIdx];
    if (!token) return new Response('missing token', { status: 400 });

    var client = event.clientId ? await self.clients.get(event.clientId) : null;
    if (!client) {
      var list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      client = list[0] || null;
    }
    if (!client) return new Response('missing client', { status: 503 });

    var meta = await askClient(client, {
      type: 'oxplayer-tdweb-stream-meta',
      token: token,
    });
    var size = Number(meta.size || 0);
    var mime = String(meta.mime || 'video/mp4');
    var tailFetchBytes = Number(meta.tailFetchBytes || 0);
    var tailMoovKnown = !!meta.tailMoovKnown;
    if (!Number.isFinite(size) || size <= 0) {
      return new Response('bad media size', { status: 500 });
    }

    if (event.request.method === 'HEAD') {
      return new Response(null, {
        status: 200,
        headers: {
          'Content-Type': mime,
          'Accept-Ranges': 'bytes',
          'Content-Length': String(size),
          'Cache-Control': 'no-store',
          'Cross-Origin-Resource-Policy': 'same-origin',
        },
      });
    }

    var rangeHeader = event.request.headers.get('range');
    var range = parseRange(rangeHeader, size);
    streamLog(
      'fetch token=' + token +
        ' range=' + String(rangeHeader || 'none') +
        ' size=' + size +
        ' mime=' + mime,
    );
    if (range == null) {
      return new Response('', {
        status: 416,
        headers: {
          'Content-Range': 'bytes */' + String(size),
          'Accept-Ranges': 'bytes',
        },
      });
    }

    var requestedStart = range.start;
    var requestedEnd = range.end;
    var span = range.end - range.start + 1;
    var maxChunk = responseChunkBytes;
    // Allow up to 64MB for tail requests so Chrome's FFmpegDemuxer gets the entire moov atom
    // in one go without disjoint range errors.
    if (range.end >= size - 1) {
      maxChunk = Math.max(maxChunk, Math.min(size, 64 * 1024 * 1024));
    }
    if (range.openEnded || span > maxChunk) {
      // For all seek requests, we must strictly respect range.start.
      // Modifying range.start creates a disjoint Content-Range which Chrome rejects
      // with PIPELINE_ERROR_READ: FFmpegDemuxer: data source error.
      range.end = Math.min(range.start + maxChunk - 1, size - 1);
      range.partial = true;
      streamLog(
        'cap range token=' + token +
          ' req=' + requestedStart + '-' + requestedEnd +
          ' capped=' + range.start + '-' + range.end +
          ' maxChunk=' + maxChunk
      );
    }

    var offset = range.start;
    var remaining = range.end - range.start + 1;
    var chunks = [];
    var totalRead = 0;
    while (remaining > 0) {
      if (event.request.signal && event.request.signal.aborted) {
        streamLog('request aborted token=' + token + ' offset=' + offset);
        return new Response('', { status: 499 });
      }
      var count = Math.min(readChunkBytes, remaining);
      var part = await askClient(client, {
        type: 'oxplayer-tdweb-stream-read',
        token: token,
        offset: offset,
        count: count,
      });
      var bytes = part.data;
      if (!(bytes instanceof Uint8Array)) {
        bytes = new Uint8Array(bytes || []);
      }
      if (bytes.length === 0) {
        throw new Error('empty tdweb stream chunk token=' + token + ' offset=' + offset);
      }
      streamLog(
        'chunk token=' + token +
          ' offset=' + offset +
          ' requested=' + count +
          ' actual=' + bytes.length,
      );
      chunks.push(bytes);
      offset += bytes.length;
      totalRead += bytes.length;
      remaining -= bytes.length;
    }

    var body = new Uint8Array(totalRead);
    var cursor = 0;
    for (var i = 0; i < chunks.length; i++) {
      body.set(chunks[i], cursor);
      cursor += chunks[i].length;
    }
    streamLog(
      'response complete token=' + token +
        ' range=' + range.start + '-' + range.end +
        ' bytes=' + body.length,
    );

    var headers = {
      'Content-Type': mime,
      'Accept-Ranges': 'bytes',
      'Content-Length': String(body.length),
      'Cache-Control': 'no-store',
      'Cross-Origin-Resource-Policy': 'same-origin',
    };
    var status = 200;
    if (range.partial) {
      status = 206;
      headers['Content-Range'] = 'bytes ' + range.start + '-' + range.end + '/' + size;
    }
    return new Response(body, { status: status, headers: headers });
  })());
});
