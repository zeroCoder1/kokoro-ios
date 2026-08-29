// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "KokoroSwift",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
  ],
  products: [
    // Keep MLX in the host process instead of creating a second dynamic copy.
    .library(name: "KokoroSwift", targets: ["KokoroSwift"]),
  ],
  dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.6"),
    // These are the engine's tested revisions. Later releases pin an older
    // exact MLX and cannot coexist with the host app's current MLX runtime.
    .package(url: "https://github.com/mlalma/MisakiSwift", exact: "1.0.3"),
    .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.5"),
  ],
  targets: [
    .target(
      name: "KokoroSwift",
      dependencies: [
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXFast", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXRandom", package: "mlx-swift"),
        .product(name: "MLXFFT", package: "mlx-swift"),
        .product(name: "MisakiSwift", package: "MisakiSwift"),
        .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
      ],
      resources: [
        .copy("../../Resources"),
      ]
    ),
    .testTarget(
      name: "KokoroSwiftTests",
      dependencies: ["KokoroSwift"]
    ),
  ]
)
