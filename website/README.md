# OXPlayer marketing site

Next.js static site for [OXPlayer](https://github.com/Gurbeh/oxplayer-client). Deployed to GitHub Pages on push to `main`.

| URL | Purpose |
|-----|---------|
| https://gurbeh.github.io/oxplayer-client/ | Landing page |
| https://gurbeh.github.io/oxplayer-client/privacy-policy.html | Play Store privacy URL (static HTML) |
| https://gurbeh.github.io/oxplayer-client/privacy-policy/ | Same policy in the site UI |

## Develop

```bash
cd website
npm ci
npm run dev
```

Open http://localhost:3000

## Production build (matches GitHub Pages)

```bash
cd website
npm ci
$env:NODE_ENV="production"   # PowerShell
npm run build
```

Output: `website/out/`. Preview with `npx serve out` at http://localhost:3000/oxplayer-client/

## Privacy policy source

- In-app page: `src/features/legal/PrivacyPolicyPage.tsx`
- Play Store HTML: `docs/privacy-policy.html` (copied to `public/` in CI before build)

Update both when policy text changes.
