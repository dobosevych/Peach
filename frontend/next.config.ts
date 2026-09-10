import type { NextConfig } from "next"

const nextConfig: NextConfig = {
  // Emit a minimal server bundle so the runtime image stays small.
  output: "standalone",
}

export default nextConfig
