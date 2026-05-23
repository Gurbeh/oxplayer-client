/**
 * Minimal bridge: Dart registers `window.oxplayerTdwebDartPush(jsonString)`,
 * then calls `oxplayerTdweb.createClient({ instanceEpoch })` and `oxplayerTdweb.send(json)`.
 * Requires `tdweb/tdweb.js` loaded first. The UMD global may be TdClient or
 * `{ default: TdClient }` (webpack ESM interop).
 */
(function () {
  'use strict';

  try {
    if (typeof globalThis.__OXPLAYER_TDWEB_PUBLIC_PATH__ === 'undefined') {
      globalThis.__OXPLAYER_TDWEB_PUBLIC_PATH__ = new URL(
        'tdweb/',
        document.baseURI,
      ).href;
    }
  } catch (_) {
    globalThis.__OXPLAYER_TDWEB_PUBLIC_PATH__ = 'tdweb/';
  }

  var client = null;
  var streamSeq = 0;
  var streamFiles = Object.create(null);
  var streamWorkerReady = null;
  var streamLogKey = '[OX_TG_WEB_STREAM]';

  function streamLog(message) {
    console.info(streamLogKey + ' ' + message);
  }

  function streamWarn(message) {
    console.warn(streamLogKey + ' ' + message);
  }

  function errorToMessage(error) {
    if (error == null) return 'unknown error';
    if (typeof error === 'string') return error;
    if (error.message) return String(error.message);
    try {
      var json = JSON.stringify(error);
      if (json && json !== '{}') return json;
    } catch (_) {}
    return String(error);
  }

  function tdwebClass() {
    var g = typeof globalThis !== 'undefined' ? globalThis : window;
    var t = g.tdweb;
    if (typeof t === 'function') return t;
    if (t && typeof t.default === 'function') return t.default;
    throw new Error(
      'Global tdweb (TdClient) missing. Ensure web/tdweb/tdweb.js is copied (node scripts/sync-tdweb.mjs), '
        + 'served at the same origin as the app, and loads before oxplayer_tdweb_bridge.js (see web/index.html).',
    );
  }

  function pushUpdate(u) {
    try {
      var t = u && u['@type'];
      if (t === 'updateFatalError') {
        // Worker passes a JS Error here; JSON.stringify(Error) becomes "{}" so Dart
        // never sees .message. Normalize to a plain string before stringify.
        var er = u && u.error;
        if (typeof er === 'string') {
          if (!er) {
            u = { '@type': 'updateFatalError', error: '(empty fatal string from TDLib)' };
          }
        } else if (er && typeof er.message === 'string' && er.message) {
          u = { '@type': 'updateFatalError', error: String(er.message) };
        } else if (er && (typeof er.stack === 'string') && er.stack) {
          u = { '@type': 'updateFatalError', error: String(er.stack) };
        } else if (er != null && typeof er === 'object') {
          var name = typeof er.name === 'string' ? er.name : 'Error';
          var msgAny = er.message || er.stack;
          if (typeof msgAny === 'string' && msgAny.trim()) {
            u = { '@type': 'updateFatalError', error: String(msgAny) };
          } else {
            u = {
              '@type': 'updateFatalError',
              error:
                'JS ' +
                name +
                ' (no message/stack; often WASM/IndexedDB or corrupt tdweb DB)',
            };
          }
        } else if (er != null) {
          u = { '@type': 'updateFatalError', error: String(er) };
        } else {
          u = {
            '@type': 'updateFatalError',
            error:
              'updateFatalError with no message (see browser DevTools console for worker errors)',
          };
        }
        console.error(streamLogKey + ' updateFatalError →', u.error);
      }
      if (t === 'updateAuthorizationState') {
        var inner =
          u.authorization_state && u.authorization_state['@type'];
        streamLog('updateAuthorizationState → ' + (inner || '?'));
      }
    } catch (_) {}
    var fn = window.oxplayerTdwebDartPush;
    if (typeof fn !== 'function') return;
    try {
      fn(JSON.stringify(u));
    } catch (e) {
      console.error('[oxplayer_tdweb_bridge] dart push failed', e);
    }
  }

  function ensureStreamWorker() {
    if (streamWorkerReady) return streamWorkerReady;
    if (!('serviceWorker' in navigator)) {
      return Promise.reject(new Error('ServiceWorker is not supported'));
    }
    streamLog('stream worker register start');
    streamWorkerReady = navigator.serviceWorker
      .register('oxplayer_tdweb_stream_sw.js', { scope: './' })
      .then(function () {
        streamLog('stream worker registered; waiting ready');
        return navigator.serviceWorker.ready;
      })
      .then(function () {
        if (navigator.serviceWorker.controller) {
          streamLog('stream worker controller ready');
          return true;
        }
        streamLog('stream worker waiting controllerchange');
        return new Promise(function (resolve, reject) {
          var timeout = setTimeout(function () {
            reject(new Error('ServiceWorker controller not ready'));
          }, 10000);
          navigator.serviceWorker.addEventListener(
            'controllerchange',
            function () {
              clearTimeout(timeout);
              streamLog('stream worker controllerchange ready');
              resolve(true);
            },
            { once: true },
          );
        });
      });
    return streamWorkerReady;
  }

  async function bytesFromReadFilePartData(data) {
    if (data instanceof Uint8Array) return data;
    if (typeof ArrayBuffer !== 'undefined' && data instanceof ArrayBuffer) return new Uint8Array(data);
    if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView && ArrayBuffer.isView(data)) {
      return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    }
    if ((typeof Blob !== 'undefined' && data instanceof Blob) ||
        (data && typeof data.arrayBuffer === 'function' && typeof data.size === 'number')) {
      streamLog('decode Blob size=' + data.size + ' type=' + (data.type || ''));
      return new Uint8Array(await data.arrayBuffer());
    }
    if (Array.isArray(data)) return Uint8Array.from(data);
    if (typeof data === 'string') {
      if (data.length === 0) return new Uint8Array(0);
      var raw = atob(data);
      var out = new Uint8Array(raw.length);
      for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i) & 255;
      return out;
    }
    if (data && typeof data === 'object') {
      if (data.data != null) return bytesFromReadFilePartData(data.data);
      if (data.bytes != null) return bytesFromReadFilePartData(data.bytes);
      var keys = Object.keys(data).filter(function (k) { return /^\d+$/.test(k); });
      keys.sort(function (a, b) { return Number(a) - Number(b); });
      var bytes = new Uint8Array(keys.length);
      for (var i = 0; i < keys.length; i++) bytes[i] = Number(data[keys[i]]) & 255;
      return bytes;
    }
    return new Uint8Array(0);
  }

  function tdwebSendWithTimeout(query, timeoutMs, label) {
    return Promise.race([
      client.send(query),
      new Promise(function (_, reject) {
        setTimeout(function () {
          reject(new Error(label + ' timed out after ' + timeoutMs + 'ms'));
        }, timeoutMs);
      }),
    ]);
  }

  async function readCachedFilePart(file, offset, count) {
    streamLog(
      'readFilePart start file_id=' + file.fileId +
        ' offset=' + offset +
        ' count=' + count,
    );
    var r = await tdwebSendWithTimeout({
      '@type': 'readFilePart',
      file_id: file.fileId,
      offset: offset,
      count: count,
    }, 5000, 'readFilePart');
    if (!r || (r['@type'] !== 'filePart' && r['@type'] !== 'data')) {
      throw new Error('readFilePart failed: ' + JSON.stringify(r));
    }
    var bytes = await bytesFromReadFilePartData(r.data);
    if (bytes.length === 0 && count !== 0) {
      streamLog(
        'readFilePart empty; retry count=0 file_id=' + file.fileId +
          ' offset=' + offset +
          ' requested=' + count +
          ' type=' + r['@type'] +
          ' dataType=' + Object.prototype.toString.call(r.data) +
          ' keys=' + Object.keys(r).join(','),
      );
      r = await tdwebSendWithTimeout({
        '@type': 'readFilePart',
        file_id: file.fileId,
        offset: offset,
        count: 0,
      }, 5000, 'readFilePart count=0');
      if (!r || (r['@type'] !== 'filePart' && r['@type'] !== 'data')) {
        throw new Error('readFilePart count=0 failed: ' + JSON.stringify(r));
      }
      bytes = await bytesFromReadFilePartData(r.data);
    }
    if (count > 0 && bytes.length > count) return bytes.slice(0, count);
    streamLog(
      'readFilePart done file_id=' + file.fileId +
        ' offset=' + offset +
        ' bytes=' + bytes.length,
    );
    return bytes;
  }

  async function readFilePartWithDownload(file, offset, count) {
    var bytes = await readCachedFilePart(file, offset, count);
    if (bytes.length > 0) return bytes;

    streamLog(
      'stream cache miss token=' + file.token +
        ' offset=' + offset +
        ' count=' + count,
    );
    await tdwebSendWithTimeout({
      '@type': 'downloadFile',
      file_id: file.fileId,
      priority: 32,
      offset: offset,
      limit: count,
      synchronous: false,
    }, 5000, 'downloadFile');

    var deadline = Date.now() + 12000;
    while (Date.now() < deadline) {
      await new Promise(function (resolve) { setTimeout(resolve, 250); });
      bytes = await readCachedFilePart(file, offset, count);
      if (bytes.length > 0) return bytes;
    }
    throw new Error(
      'TDLib file range not readable after download: file_id=' + file.fileId +
        ' offset=' + offset +
        ' count=' + count,
    );
  }

  /**
   * Infer container MIME from first bytes so SW Content-Type matches bytes (FFmpeg demuxer).
   * @param {Uint8Array} u8
   * @returns {string|null}
   */
  function readU32Be(u8, o) {
    return ((u8[o] << 24) | (u8[o + 1] << 16) | (u8[o + 2] << 8) | u8[o + 3]) >>> 0;
  }

  function moovBoxSizeAt(u8, boxStart) {
    if (boxStart + 8 > u8.length) return 0;
    var boxSize = readU32Be(u8, boxStart);
    if (boxSize === 1 && boxStart + 16 <= u8.length) {
      var hi = readU32Be(u8, boxStart + 8);
      var lo = readU32Be(u8, boxStart + 12);
      boxSize = hi * 0x100000000 + lo;
    }
    return boxSize >= 8 ? boxSize : 0;
  }

  /** @returns {{ start: number, size: number }|null} absolute file offsets */
  function findMoovBoxInBuffer(u8, baseOffset) {
    var found = null;
    for (var i = 0; i + 8 <= u8.length; ) {
      var boxSize = readU32Be(u8, i);
      if (boxSize === 1) {
        if (i + 16 > u8.length) break;
        var hi = readU32Be(u8, i + 8);
        var lo = readU32Be(u8, i + 12);
        boxSize = hi * 0x100000000 + lo;
      }
      if (boxSize < 8 || i + boxSize > u8.length) break;
      if (u8[i + 4] === 0x6d && u8[i + 5] === 0x6f && u8[i + 6] === 0x6f && u8[i + 7] === 0x76) {
        found = { start: baseOffset + i, size: boxSize };
      }
      i += boxSize;
    }
    if (found != null) return found;
    for (var k = 4; k + 4 <= u8.length; k++) {
      if (u8[k] !== 0x6d || u8[k + 1] !== 0x6f || u8[k + 2] !== 0x6f || u8[k + 3] !== 0x76) {
        continue;
      }
      var boxStart = k - 4;
      var sz = moovBoxSizeAt(u8, boxStart);
      if (sz >= 8) {
        return { start: baseOffset + boxStart, size: sz };
      }
    }
    return null;
  }

  function sniffFragmentedMp4(u8) {
    if (!u8 || u8.length < 8) return false;
    for (var k = 4; k + 4 <= Math.min(u8.length, 512 * 1024); k++) {
      if (u8[k] === 0x6d && u8[k + 1] === 0x6f && u8[k + 2] === 0x6f && u8[k + 3] === 0x66) {
        return true;
      }
    }
    return false;
  }

  function computeTailFetchBytes(fileSize, tailProbe) {
    var base = fileSize - tailProbe.length;
    var moov = findMoovBoxInBuffer(tailProbe, base);
    if (moov != null && moov.size > 0) {
      var bytesFromMoovStart = fileSize - moov.start;
      return Math.min(fileSize, Math.max(2 * 1024 * 1024, bytesFromMoovStart + 256 * 1024));
    }
    return Math.min(fileSize, 64 * 1024 * 1024);
  }

  async function probeMoovAndAudioForWeb(file, size) {
    var moov = null;
    var audioCodec = null;
    var fragmented = false;
    var headLen = Math.min(size, 8 * 1024 * 1024);
    if (headLen > 0) {
      var head = await readFilePartWithDownload(file, 0, headLen);
      fragmented = sniffFragmentedMp4(head);
      if (!audioCodec) audioCodec = sniffAudioCodecFromBytes(head);
      moov = findMoovBoxInBuffer(head, 0);
      if (moov != null) {
        streamLog('stream moov at head start=' + moov.start + ' size=' + moov.size);
      }
    }
    var steps = [4, 8, 16, 32, 64];
    var lastTail = null;
    var lastLen = 0;
    if (moov == null) {
      for (var i = 0; i < steps.length; i++) {
        var probeLen = Math.min(size, steps[i] * 1024 * 1024);
        if (probeLen <= 0 || probeLen === lastLen) continue;
        var tail = await readFilePartWithDownload(file, size - probeLen, probeLen);
        lastTail = tail;
        lastLen = probeLen;
        if (!audioCodec) audioCodec = sniffAudioCodecFromBytes(tail);
        if (!fragmented) fragmented = sniffFragmentedMp4(tail);
        moov = findMoovBoxInBuffer(tail, size - tail.length);
        if (moov != null) break;
      }
    }
    var tailFetchBytes = lastTail != null ? computeTailFetchBytes(size, lastTail) : Math.min(size, 64 * 1024 * 1024);
    if (moov == null) {
      tailFetchBytes = Math.max(tailFetchBytes, Math.min(size, 64 * 1024 * 1024));
    }
    var webPlaybackRisk = null;
    if (audioCodec === 'ac3' || audioCodec === 'eac3') {
      webPlaybackRisk = audioCodec;
    } else if (fragmented) {
      webPlaybackRisk = 'fragmented_mp4';
    } else if (moov == null) {
      webPlaybackRisk = 'moov_not_found';
    }
    return {
      moov: moov,
      audioCodec: audioCodec,
      tailFetchBytes: tailFetchBytes,
      probedBytes: lastLen,
      fragmented: fragmented,
      webPlaybackRisk: webPlaybackRisk,
    };
  }

  function sniffAudioCodecFromBytes(u8) {
    if (!u8 || u8.length < 16) return null;
    var ascii = '';
    for (var j = 0; j < Math.min(u8.length, 512 * 1024); j++) {
      var c = u8[j];
      if (c >= 32 && c <= 126) ascii += String.fromCharCode(c);
    }
    var lower = ascii.toLowerCase();
    if (lower.indexOf('ac-3') >= 0 || lower.indexOf('dac3') >= 0 || lower.indexOf('ac3') >= 0) {
      return 'ac3';
    }
    if (lower.indexOf('ec-3') >= 0 || lower.indexOf('dec3') >= 0 || lower.indexOf('eac3') >= 0) {
      return 'eac3';
    }
    if (lower.indexOf('mp4a') >= 0) return 'aac';
    return null;
  }

  function sniffVideoCodecFromBytes(u8) {
    if (!u8 || u8.length < 16) return null;
    var ascii = '';
    for (var j = 0; j < Math.min(u8.length, 256 * 1024); j++) {
      var c = u8[j];
      if (c >= 32 && c <= 126) ascii += String.fromCharCode(c);
      else if (ascii.length > 0 && ascii.length < 4) ascii = '';
    }
    if (ascii.indexOf('hvc1') >= 0 || ascii.indexOf('hev1') >= 0 || ascii.indexOf('hvcC') >= 0) {
      return 'hevc';
    }
    if (ascii.indexOf('avc1') >= 0 || ascii.indexOf('avcC') >= 0) return 'h264';
    return null;
  }

  function sniffContainerMimeFromBytes(u8) {
    if (!u8 || u8.length < 12) return null;
    if (u8[0] === 0x1a && u8[1] === 0x45 && u8[2] === 0xdf && u8[3] === 0xa3) {
      var ascii = '';
      for (var j = 4; j < Math.min(u8.length, 4096); j++) {
        var c = u8[j];
        if (c >= 32 && c <= 126) ascii += String.fromCharCode(c);
      }
      if (ascii.indexOf('webm') >= 0) return 'video/webm';
      return 'video/x-matroska';
    }
    for (var o = 0; o + 8 <= u8.length && o < 65536; ) {
      var boxSize =
        ((u8[o] << 24) | (u8[o + 1] << 16) | (u8[o + 2] << 8) | u8[o + 3]) >>> 0;
      if (boxSize < 8 || o + boxSize > u8.length) break;
      if (u8[o + 4] === 0x66 && u8[o + 5] === 0x74 && u8[o + 6] === 0x79 && u8[o + 7] === 0x70) {
        return 'video/mp4';
      }
      if (boxSize === 1) break;
      o += boxSize;
    }
    return null;
  }

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', async function (event) {
      var msg = event.data || {};
      var port = event.ports && event.ports[0];
      if (!port) return;
      try {
        if (msg.type === 'oxplayer-tdweb-stream-meta') {
          var meta = streamFiles[msg.token];
          if (!meta) throw new Error('unknown stream token ' + msg.token);
          streamLog(
            'stream meta token=' + msg.token +
              ' size=' + meta.size +
              ' mime=' + meta.mime +
              ' pathLen=' + meta.path.length,
          );
          port.postMessage({
            ok: true,
            size: meta.size,
            mime: meta.mime,
            tailFetchBytes: meta.tailFetchBytes || 0,
            tailMoovKnown: !!meta.tailMoovKnown,
            audioCodec: meta.audioCodec || null,
          });
          return;
        }
        if (msg.type === 'oxplayer-tdweb-stream-read') {
          var file = streamFiles[msg.token];
          if (!file) throw new Error('unknown stream token ' + msg.token);
          var offset = Number(msg.offset || 0);
          var count = Number(msg.count || 0);
          streamLog(
            'stream read token=' + msg.token +
              ' offset=' + offset +
              ' count=' + count,
          );
          var bytes = await readFilePartWithDownload(file, offset, count);
          if (offset === 0 && bytes.length > 0) {
            var sample = Array.prototype.slice.call(bytes, 0, Math.min(16, bytes.length))
              .map(function (b) { return b.toString(16).padStart(2, '0'); })
              .join(' ');
            streamLog('stream first bytes token=' + msg.token + ' ' + sample);
          }
          streamLog(
            'stream read ok token=' + msg.token +
              ' offset=' + offset +
              ' bytes=' + bytes.length,
          );
          port.postMessage({ ok: true, data: bytes }, [bytes.buffer]);
          return;
        }
      } catch (e) {
        streamWarn('stream message failed ' + (e && e.message ? e.message : String(e)));
        port.postMessage({ ok: false, error: e && e.message ? e.message : String(e) });
      }
    });
  }

  window.oxplayerTdweb = {
    /**
     * @param {{ instanceEpoch?: number, mode?: string }} opts
     * @returns {Promise<void>}
     */
    createClient: function (opts) {
      if (client) {
        return Promise.reject(new Error('TdClient already created'));
      }
      opts = opts || {};
      var epoch = opts.instanceEpoch != null ? opts.instanceEpoch : 0;
      var TdClient = tdwebClass();
      streamLog('createClient epoch=' + String(epoch));
      client = new TdClient({
        instanceName: 'oxplayer_td_' + String(epoch),
        mode: opts.mode || 'wasm',
        onUpdate: pushUpdate,
        useDatabase: true,
      });
      return Promise.resolve();
    },

    /** True after tdweb worker has fired `inited` (safe to call [send]). */
    isTdwebInited: function () {
      return !!(client && client.isInited);
    },

    /** @returns {Promise<void>} */
    closeClient: function () {
      if (!client) return Promise.resolve();
      try {
        client.close();
      } catch (e) {
        streamWarn('client.close ' + (e && e.message ? e.message : String(e)));
      }
      client = null;
      return Promise.resolve();
    },

    /**
     * @param {string} jsonStr
     * @returns {Promise<string>}
     */
    send: function (jsonStr) {
      if (!client) {
        return Promise.reject(new Error('TdClient not initialized'));
      }
      var q = JSON.parse(jsonStr);
      // Flat `setTdlibParameters` (Dart wire JSON). Do not nest under `parameters`: tdweb's
      // worker prepareQuery patches root fields then td_send(JSON.stringify(query)).
      var qt = q && q['@type'];
      if (qt) {
        streamLog('send → ' + qt);
      }
      return client.send(q).then(function (r) {
        return JSON.stringify(r);
      }).catch(function (e) {
        var msg = errorToMessage(e);
        streamWarn('send failed ' + (qt || '?') + ' ' + msg);
        if (e && e['@type'] === 'error') {
          return JSON.stringify(e);
        }
        return JSON.stringify({ '@type': 'error', 'code': 500, 'message': msg });
      });
    },

    /**
     * Reads a completed TDLib cached file from tdweb's virtual FS and exposes it
     * as a browser-playable blob: URL.
     *
     * @param {number} fileId TDLib file.id
     * @param {string} path TDLib local.path, used only for diagnostics.
     * @param {number} size Expected byte length; must be > 0.
     * @param {string=} mime MIME type for Blob.
     * @returns {Promise<string>}
     */
    createObjectUrlForTdFile: async function (fileId, path, size, mime) {
      if (!client) {
        return Promise.reject(new Error('TdClient not initialized'));
      }
      fileId = Number(fileId || 0);
      path = String(path || '');
      size = Number(size || 0);
      mime = String(mime || 'video/mp4');
      if (!Number.isFinite(fileId) || fileId <= 0) {
        return Promise.reject(new Error('TDLib file id is invalid'));
      }
      if (!path) {
        return Promise.reject(new Error('TDLib file path is empty'));
      }
      if (!Number.isFinite(size) || size <= 0) {
        return Promise.reject(new Error('TDLib file size is unknown'));
      }
      streamLog('createObjectUrlForTdFile file_id=' + fileId + ' pathLen=' + path.length + ' size=' + size);
      var chunks = [];
      var offset = 0;
      var chunkSize = 2 * 1024 * 1024;
      while (offset < size) {
        var count = Math.min(chunkSize, size - offset);
        var r = await tdwebSendWithTimeout({
          '@type': 'readFilePart',
          file_id: fileId,
          offset: offset,
          count: count,
        }, 5000, 'readFilePart object URL');
        if (!r || (r['@type'] !== 'filePart' && r['@type'] !== 'data')) {
          throw new Error('readFilePart failed at offset ' + offset + ': ' + JSON.stringify(r));
        }
        var bytes = await bytesFromReadFilePartData(r.data);
        if (bytes.length === 0) {
          throw new Error('readFilePart returned empty data at offset ' + offset);
        }
        chunks.push(bytes);
        offset += bytes.length;
        if (bytes.length < count) break;
      }
      var blob = new Blob(chunks, { type: mime || 'application/octet-stream' });
      var url = URL.createObjectURL(blob);
      streamLog('blob URL ready size=' + blob.size + ' type=' + blob.type);
      return url;
    },

    /**
     * Creates a same-origin streaming URL. The service worker serves HTTP byte
     * ranges and reads tdweb cached file parts on demand via readFilePart.
     *
     * @param {number} fileId TDLib file.id
     * @param {string} path TDLib local.path
     * @param {number} size Expected byte length; must be > 0.
     * @param {string=} mime MIME type.
     * @returns {Promise<string>} JSON string `{ "url": string|null, "sniffedMime": string }`. `url` is null when the probed container cannot play in the browser video stack (e.g. Matroska/MKV).
     */
    createStreamUrlForTdFile: async function (fileId, path, size, mime) {
      fileId = Number(fileId || 0);
      path = String(path || '');
      size = Number(size || 0);
      mime = String(mime || 'video/mp4');
      if (!client) throw new Error('TdClient not initialized');
      if (!Number.isFinite(fileId) || fileId <= 0) throw new Error('TDLib file id is invalid');
      if (!path) throw new Error('TDLib file path is empty');
      if (!Number.isFinite(size) || size <= 0) throw new Error('TDLib file size is unknown');
      streamLog('stream URL create start file_id=' + fileId + ' size=' + size);
      await ensureStreamWorker();
      var token = String(++streamSeq) + '_' + String(Date.now());
      var file = { token: token, fileId: fileId, path: path, size: size, mime: mime };
      streamLog('stream probe start token=' + token);
      var probe = await readFilePartWithDownload(file, 0, 64 * 1024);
      if (!probe || probe.length === 0) {
        throw new Error('TDLib stream probe returned no bytes for file_id=' + fileId);
      }
      var sample = Array.prototype.slice.call(probe, 0, Math.min(16, probe.length))
        .map(function (b) { return b.toString(16).padStart(2, '0'); })
        .join(' ');
      streamLog('stream probe ok token=' + token + ' bytes=' + probe.length + ' first=' + sample);
      var sniffed = sniffContainerMimeFromBytes(probe);
      if (sniffed) {
        file.mime = sniffed;
        streamLog('stream mime sniff → ' + sniffed + ' (declared=' + mime + ')');
      }
      var codec = sniffVideoCodecFromBytes(probe);
      if (codec) {
        streamLog('stream codec sniff → ' + codec + (codec === 'hevc' ? ' (needs HEVC in browser)' : ''));
      }
      // Lightweight codec/risk sniff from the 64KB probe — no heavy moov/tail scanning.
      // Chrome's <video> handles moov discovery via its own byte-range seeks.
      var audioCodec = sniffAudioCodecFromBytes(probe);
      var webPlaybackRisk = null;
      if (audioCodec === 'ac3' || audioCodec === 'eac3') {
        webPlaybackRisk = audioCodec;
      }
      if (sniffFragmentedMp4(probe)) {
        webPlaybackRisk = webPlaybackRisk || 'fragmented_mp4';
        streamLog('stream fragmented MP4 (moof) — Chrome progressive <video> often fails');
      }
      file.tailFetchBytes = 0;
      file.tailMoovKnown = false;
      file.webPlaybackRisk = webPlaybackRisk;
      if (audioCodec) {
        file.audioCodec = audioCodec;
        streamLog(
          'stream audio sniff → ' + audioCodec +
            (audioCodec === 'ac3' || audioCodec === 'eac3'
              ? ' (often unsupported in Chrome <video>; Android MPV works)'
              : ''),
        );
      }
      streamLog(
        'stream skip heavy moov probe — Chrome will range-seek for moov on demand',
      );
      streamFiles[token] = file;
      var extFromMime = 'mp4';
      if (file.mime.indexOf('matroska') >= 0 || file.mime === 'video/x-matroska') {
        extFromMime = 'mkv';
      } else if (file.mime.indexOf('webm') >= 0) {
        extFromMime = 'webm';
      }
      var baseName = 'telegram-video';
      try {
        var parts = path.split(/[\\/]/).filter(Boolean);
        var last = parts[parts.length - 1];
        if (last) {
          var dot = last.lastIndexOf('.');
          baseName = dot > 0 ? last.slice(0, dot) : last;
        }
      } catch (_) {}
      var safeName = encodeURIComponent(baseName + '.' + extFromMime);
      var url = new URL('__ox_tdweb_stream/' + token + '/' + safeName, document.baseURI).href;
      streamLog(
        'stream URL ready token=' + token + ' size=' + size + ' mime=' + file.mime +
          (webPlaybackRisk ? ' webPlaybackRisk=' + webPlaybackRisk : ''),
      );
      return JSON.stringify({
        url: url,
        sniffedMime: file.mime,
        webPlaybackRisk: webPlaybackRisk || null,
      });
    },
  };
})();
