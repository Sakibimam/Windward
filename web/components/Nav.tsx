"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
  { href: "/", label: "Overview" },
  { href: "/demo", label: "Live demo" },
  { href: "/about", label: "Method" },
  { href: "/docs", label: "Docs" },
];

export default function Nav() {
  const path = usePathname();
  return (
    <nav className="nav">
      <div className="shell nav-in">
        <Link href="/" className="brand" aria-label="Windward home">
          <Image
            src="/windward-mark.png"
            alt=""
            width={30}
            height={30}
            className="brand-mark"
            priority
          />
          <span className="brand-name">Windward</span>
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
          </div>
          <a
            className="nav-cta"
            href="https://github.com/Sakibimam/Windward"
            target="_blank"
            rel="noreferrer"
          >
            View the code
          </a>
      </div>
    </nav>
  );
}
