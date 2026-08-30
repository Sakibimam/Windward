import type { NextConfig } from "next";

// Static export: the site is a build artifact that can be opened from disk or dropped on any
// host. Judges should not need a server running to look at it.
const nextConfig: NextConfig = {
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
