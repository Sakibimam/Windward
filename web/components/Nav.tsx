"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
  { href: "/", label: "Overview" },
  { href: "/demo", label: "Live demo" },
  { href: "/about", label: "Method" },
];

export default function Nav() {
  const path = usePathname();
  return (
    <nav className="nav">
      <div className="shell nav-in">
        <Link href="/" className="brand">
          <span className="mark" aria-hidden="true" />
          Windward
        </Link>
        <div className="nav-links">
          {LINKS.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className={`nav-l${path === l.href ? " on" : ""}`}
              aria-current={path === l.href ? "page" : undefined}
            >
              {l.label}
            </Link>
          ))}
          <a
            className="nav-l ext"
            href="https://github.com/Sakibimam/Windward"
            target="_blank"
            rel="noreferrer"
          >
            GitHub ↗
          </a>
        </div>
      </div>
    </nav>
  );
}
