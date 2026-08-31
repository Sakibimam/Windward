import Image from "next/image";

export default function Footer() {
  return (
    <footer className="foot">
      <div className="shell">
        <div className="foot-top">
          <Image src="/windward-mark.png" alt="" width={26} height={26} className="brand-mark" />
          <span className="brand-name">Windward</span>
        </div>
        <p>
          Every figure on this site is generated from the committed study output —{" "}
          <code>analysis/run.sh</code> rebuilds all of it from the chain. The simulator runs a
          BigInt port of <code>Volatility.sol</code>, pinned to the same fixed vector as the
          Solidity and Python models.
        </p>
        <p className="dim">
          Not audited. Prototype. Must not secure real funds. MIT licensed. UHI10 Hookathon.
        </p>
      </div>
    </footer>
  );
}
