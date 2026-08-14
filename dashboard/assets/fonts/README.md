# Offline Noto font bundle

The dashboard deliberately does not load fonts from Google at runtime. Bundle
the required Noto Sans families here during the Firebase Hosting build for
devices that do not provide them: base, Devanagari, Bengali, Gujarati,
Gurmukhi, Kannada, Malayalam, Tamil, Telugu, Oriya, Arabic, Ol Chiki, and
Meetei Mayek. The shared Flutter token stack and `web/index.html` use exactly
these fallbacks, covering the scripts used across Bhashini's 22 target Indian
languages.
