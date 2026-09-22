# GitHub HTML conformance fixtures

Recorded on 2026-09-22 with `POST /markdown`, `{ "mode": "gfm", "text": ... }`.
Each case stores its input, unmodified API response, and normalized semantic DOM.
The tests use only the checked-in files and stub media responses.

`review-summary.md` reproduces the original reported screenshot's visible
summary, commit and fractional timestamp. The disclosure's complete boilerplate
comes from the same live [Codex comment template](https://github.com/moonbitlang/openseek/pull/1713#issuecomment-5770540925),
captured on 2026-09-22; the original comment may have been updated since the
screenshot. Its `.github.html` is an API response for this saved reproduction.

References: [GFM raw HTML and tagfilter](https://github.github.com/gfm/#raw-html),
[GitHub's rendering pipeline](https://github.com/github/markup#github-markup),
and [relative-time-element](https://github.com/github/relative-time-element).
GitHub's API is an observation, not a versioned specification: review changes
when explicitly refreshing these fixtures.

`node desktop/e2e/fixtures/github-markdown/record.mjs` regenerates only the
normalization. Add `--fetch` to query GitHub again using the saved inputs.

The projection strips GitHub's heading/table/picture/image-link wrappers,
generated classes/styles and image proxy URLs. It also normalizes URLs against
the PR URL, ignores external-link target/rel and the local video's metadata
preload, unwraps GitHub-generated user-mention links (the existing local link
policy is unchanged), and collapses formatting whitespace. It retains semantic nesting,
tag names, text, and other attributes. Input class/style/event filtering is
additionally checked against the live DOM in the adversarial browser test.

The application uses the requested fixed tag list (unsupported wrappers are
removed while keeping their content), original media URLs and local Rabbita
code blocks. Its picture sources retain safe srcset descriptors; GitHub's
proxy rewrites these. Videos always have controls and never autoplay. GitHub
retains datetime on relative-time but removes its input formatting options;
the bundled 5.3.1 component supplies formatting and automatic updates.

`clip.webm` is a two-second synthetic FFmpeg test pattern for offline playback:
`ffmpeg -f lavfi -i testsrc2=size=160x90:rate=10:duration=2 -c:v libvpx -b:v 80k -an clip.webm`.
