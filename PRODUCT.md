# Product

## Register

product

## Users

The owner of a personal, self-curated film and TV collection (folders organised by Kodi / Jellyfin / tinyMediaManager, with NFO metadata and posters). They browse and watch mostly **at night, in a dim bedroom or living room, holding an Android tablet** on the sofa or in bed. Secondary contexts: a phone, and occasionally a Mac or Windows PC for managing the library.

The job on almost every screen is the same: *decide what to watch next, then start it with as little friction as possible*. Library management (adding folders, rescanning, updates) is occasional and should stay out of the way.

## Product Purpose

MyVidhub turns a folder of video files into a private cinema: a poster wall built from the user's own NFO metadata and artwork, with a player strong enough for any file (MKV, HEVC, HDR, ASS subtitles). It exists because the user wants an Infuse / VidHub class experience on Android tablets, without a server.

Success looks like: opening the app at night feels like the lights going down in a good cinema. The artwork carries the screen, the chrome recedes, and "continue watching" is one tap away.

## Brand Personality

**Refined, fluid, tactile.** Calm and confident rather than loud. Closest reference is the **Apple TV app**: generous artwork, quiet typography with precise hierarchy, restrained colour, material (blur, light, depth) used sparingly and on purpose, motion that is smooth but never showy.

Emotional goal: the user should feel their collection looks *expensive* and cared for.

## Anti-references

- **Default Android Material.** Stock NavigationBar / NavigationRail with pill indicators, stock ChoiceChips, FilledButton shapes, tonal surfaces, ripple-everything. This is the user's main complaint about the current UI.
- Generic "streaming service" clones: red/gold brand colour splashed everywhere, loud badges, carousel overload.
- Gamer / neon dark mode, gradient text, glassmorphism on every surface.
- Dashboard aesthetics: cards inside cards, uniform grids of identical tiles, settings that look like an admin panel.

## Design Principles

1. **Artwork first, chrome second.** Posters and backdrops are the colour and the hierarchy. UI elements are neutral, thin, and quiet so the user's own collection is what looks beautiful.
2. **Built for the dark room.** Low-glare surfaces, no pure white blocks, comfortable contrast for text over imagery, nothing that flashes or blinds when the screen wakes up at night.
3. **One obvious next action.** Each screen makes "play / continue" the clearest thing on it. Everything else is secondary and visually subordinate.
4. **Earned material.** Blur, depth, and motion appear only where they explain something (layering over artwork, focus, transitions), never as decoration. Motion is short and calm.
5. **Feel native to nothing.** It should not read as stock Android or as a Material demo; it should read as its own considered product on every platform.

## Accessibility & Inclusion

- No special WCAG target beyond solid readability: body text at least 4.5:1 against its actual background, including text placed over artwork (use scrims, not hope).
- **Keep animation minimal**, and respect the system "reduce motion" setting (`MediaQuery.disableAnimations`): no scaling / sliding transitions when it is on.
- Touch targets ≥ 48dp on tablet and phone; keyboard and D-pad focus must remain clearly visible.
