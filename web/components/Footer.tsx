import Image from "next/image";
import Link from "next/link";

const REPO = "https://github.com/Sakibimam/Windward";

const SITE = [
  { href: "/", label: "Overview" },
  { href: "/demo", label: "Live demo" },
  { href: "/about", label: "Method" },
  { href: "/docs", label: "Docs" },
];

const SOURCE = [
  { href: REPO, label: "Repository" },
  { href: `${REPO}/blob/main/THREAT_MODEL.md`, label: "Threat model" },
  { href: `${REPO}/blob/main/DECISIONS.md`, label: "Decision log" },
  { href: `${REPO}/blob/main/LICENSE`, label: "MIT licence" },
];

export default function Footer() {
  return (
    <footer className="foot">
      <div className="shell">
        <div className="foot-grid">
          <div className="foot-brand">
            <div className="foot-top">
              <Image src="/windward-mark.png" alt="" width={26} height={26} className="brand-mark" />
              <span className="brand-name">Windward</span>
            </div>
            <p className="foot-blurb">
              A volatility-adaptive fee hook for Uniswap v4, built for the UHI10 Hookathon.
            </p>
            <div className="socials">
              <a
                href="https://x.com/hisakibimam"
                target="_blank"
                rel="noreferrer"
                className="social"
                aria-label="Sakib Imam on X"
              >
                <svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true" fill="currentColor">
                  <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                </svg>
                <span>@hisakibimam</span>
              </a>
              <a
                href="https://github.com/Sakibimam"
                target="_blank"
                rel="noreferrer"
                className="social"
                aria-label="Sakib Imam on GitHub"
              >
                <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" fill="currentColor">
                  <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.4 7.4 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8" />
                </svg>
                <span>Sakibimam</span>
              </a>
            </div>
          </div>

          <nav className="foot-col" aria-label="Site">
            <h4>Site</h4>
            {SITE.map((l) => (
              <Link key={l.href} href={l.href}>{l.label}</Link>
            ))}
          </nav>

          <nav className="foot-col" aria-label="Source">
            <h4>Source</h4>
            {SOURCE.map((l) => (
              <a key={l.href} href={l.href} target="_blank" rel="noreferrer">{l.label}</a>
            ))}
          </nav>

          <div className="foot-col">
            <h4>Provenance</h4>
            <p className="foot-note">
              Every figure here is generated from committed study output.{" "}
              <code>analysis/run.sh</code> rebuilds all of it from the chain.
            </p>
          </div>
        </div>

        <div className="foot-bar">
          <p className="dim">© {new Date().getFullYear()} Windward · MIT licensed</p>
          <p className="dim">
            Unaudited prototype · testnet only · one security finding open
          </p>
        </div>
      </div>
    </footer>
  );
}
