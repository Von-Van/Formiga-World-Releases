// Release repositories, asset names, fallbacks and availability live here.
//
// status:
//   "available" — downloadable. The page asks GitHub for the newest public release (no drafts or
//                 prereleases) and falls back to `fallback` if GitHub cannot be reached.
//   "soon"      — shown with its ticket greyed out: built, but not yet published.
//   "workshop"  — shown as in development.
//
// `assets` are regular expressions matched against a release's file names, per platform.
// `fallback.files` are the exact names in `fallback.tag`, used when the live lookup fails.

window.FORMIGA = {
  // Set true when the builds are signed to hide the first-launch instructions.
  signed: false,

  components: [
    {
      id: "desktop",
      name: "Formiga Desktop",
      line: "A colony of creatures for your desktop",
      status: "available",
      required: true,
      repo: "Von-Van/Formiga-Desktop",
      assets: {
        mac: "macOS-universal\\.dmg$",
        windows: "windows-x64\\.msi$",
      },
      fallback: {
        tag: "v0.67.14",
        files: {
          mac: "Formiga-0.67.14-macOS-universal.dmg",
          windows: "Formiga-0.67.14-windows-x64.msi",
        },
      },
      size: { mac: "macOS 14 or later · Intel and Apple silicon", windows: "Windows 10 or 11 · 64-bit Intel or AMD" },
    },
    {
      id: "hill",
      name: "Formiga Hill",
      line: "Places to explore with your colony",
      status: "available",
      needs: "Formiga Desktop 0.66.4 or later",
      repo: "Von-Van/Formiga-Hill",
      assets: {
        mac: "macOS.*\\.dmg$",
        windows: "windows.*\\.msi$",
      },
      fallback: {
        tag: "v0.67.14",
        files: {
          mac: "Formiga-Hill-0.67.14-macOS-universal.dmg",
          windows: "Formiga-Hill-0.67.14-windows-x64.msi",
        },
      },
      size: { mac: "macOS 14 or later · Intel and Apple silicon", windows: "Windows 10 or 11 · 64-bit Intel or AMD" },
    },
    {
      id: "home",
      name: "Formiga Home",
      line: "A dollhouse for your creatures",
      status: "available",
      needs: "Formiga Desktop 0.67.0 or later",
      repo: "Von-Van/Formiga-Home",
      assets: {
        mac: "macOS.*\\.dmg$",
        windows: "windows.*\\.msi$",
      },
      fallback: {
        tag: "v0.67.14",
        files: {
          mac: "Formiga-Home-0.67.14-macOS-universal.dmg",
          windows: "Formiga-Home-0.67.14-windows-x64.msi",
        },
      },
      size: { mac: "macOS 14 or later · Intel and Apple silicon", windows: "Windows 10 or 11 · 64-bit Intel or AMD" },
    },
    {
      id: "battle",
      name: "Formiga Battle",
      line: "Friendly three-a-side matches for your companions",
      status: "available",
      needs: "Formiga Desktop 0.67.9 or later",
      // Formiga-World-Releases builds Battle and keeps its downloads,
      // under tags like battle-v0.67.8.
      repo: "Von-Van/Formiga-World-Releases",
      assets: {
        mac: "^Formiga-Battle-.*macOS.*\\.dmg$",
        windows: "^Formiga-Battle-.*windows.*\\.msi$",
      },
      fallback: {
        tag: "battle-v0.67.14",
        files: {
          mac: "Formiga-Battle-0.67.14-macOS-universal.dmg",
          windows: "Formiga-Battle-0.67.14-windows-x64.msi",
        },
      },
      size: { mac: "macOS 14 or later · Intel and Apple silicon", windows: "Windows 10 or 11 · 64-bit Intel or AMD" },
    },
  ],
};
