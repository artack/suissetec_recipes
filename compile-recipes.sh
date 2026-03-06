#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if ! command -v php >/dev/null 2>&1; then
  echo "Error: php is required to compile recipes." >&2
  exit 1
fi

php <<'PHP'
<?php

declare(strict_types=1);

$root = getcwd();
if ($root === false) {
    fwrite(STDERR, "Unable to determine working directory.\n");
    exit(1);
}

$indexPath = $root . '/index.json';
$aliasesPath = $root . '/aliases.json';
$buildDir = $root . '/build';
$srcDir = $root . '/src';
$existingIndex = [];
if (is_file($indexPath)) {
    $decoded = json_decode((string) file_get_contents($indexPath), true);
    if (is_array($decoded)) {
        $existingIndex = $decoded;
    }
}

$recipesByPackage = [];
$compiledCount = 0;

if (!is_dir($buildDir) && !mkdir($buildDir, 0777, true) && !is_dir($buildDir)) {
    fwrite(STDERR, "Unable to create build directory.\n");
    exit(1);
}

$existingBuildArtifacts = glob($buildDir . '/*.json');
if ($existingBuildArtifacts !== false) {
    foreach ($existingBuildArtifacts as $artifact) {
        @unlink($artifact);
    }
}

$vendorDirs = glob($srcDir . '/*', GLOB_ONLYDIR);
if ($vendorDirs === false) {
    fwrite(STDERR, "Unable to scan repository.\n");
    exit(1);
}

sort($vendorDirs, SORT_STRING);

foreach ($vendorDirs as $vendorDir) {
    $vendor = basename($vendorDir);

    $packageDirs = glob($vendorDir . '/*', GLOB_ONLYDIR);
    if ($packageDirs === false) {
        continue;
    }
    sort($packageDirs, SORT_STRING);

    foreach ($packageDirs as $packageDir) {
        $package = basename($packageDir);
        $fullPackage = $vendor . '/' . $package;

        $versionDirs = glob($packageDir . '/*', GLOB_ONLYDIR);
        if ($versionDirs === false) {
            continue;
        }
        sort($versionDirs, SORT_STRING);

        foreach ($versionDirs as $versionDir) {
            $version = basename($versionDir);
            $manifestPath = $versionDir . '/manifest.json';
            if (!is_file($manifestPath)) {
                continue;
            }

            $manifest = json_decode((string) file_get_contents($manifestPath), true);
            if (!is_array($manifest)) {
                fwrite(STDERR, "Invalid JSON: {$manifestPath}\n");
                exit(1);
            }

            $files = [];
            $iterator = new RecursiveIteratorIterator(
                new RecursiveDirectoryIterator($versionDir, FilesystemIterator::SKIP_DOTS)
            );

            foreach ($iterator as $fileInfo) {
                if (!$fileInfo instanceof SplFileInfo || !$fileInfo->isFile()) {
                    continue;
                }

                $absolutePath = $fileInfo->getPathname();
                if ($absolutePath === false || $absolutePath === $manifestPath) {
                    continue;
                }

                $relativePath = substr($absolutePath, strlen($versionDir) + 1);
                if ($relativePath === false) {
                    continue;
                }

                $content = (string) file_get_contents($absolutePath);
                $files[str_replace('\\', '/', $relativePath)] = [
                    'contents' => base64_encode($content),
                    'executable' => is_executable($absolutePath),
                ];
            }

            ksort($files, SORT_STRING);

            $compiled = [
                'manifests' => [
                    $fullPackage => [
                        'manifest' => $manifest,
                        'files' => $files,
                        'ref' => $existingIndex['branch'] ?? 'main',
                    ],
                ],
            ];

            $packageDotted = str_replace('/', '.', $fullPackage);
            $compiledFilename = $packageDotted . '.' . $version . '.json';
            $compiledPath = $buildDir . '/' . $compiledFilename;

            $compiledJson = json_encode($compiled, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
            file_put_contents($compiledPath, $compiledJson);
            @unlink($root . '/' . $compiledFilename);

            $recipesByPackage[$fullPackage] ??= [];
            $recipesByPackage[$fullPackage][] = $version;
            $compiledCount++;
        }
    }
}

if ($compiledCount === 0) {
    fwrite(STDERR, "No recipes found. Expected directories like src/vendor/package/version/manifest.json\n");
    exit(1);
}

ksort($recipesByPackage, SORT_STRING);
foreach ($recipesByPackage as &$versions) {
    sort($versions, SORT_STRING);
}
unset($versions);

$knownPackages = array_keys($recipesByPackage);
$knownPackageSet = array_fill_keys($knownPackages, true);
$existingAliases = [];
if (is_file($aliasesPath)) {
    $decodedAliases = json_decode((string) file_get_contents($aliasesPath), true);
    if (is_array($decodedAliases['aliases'] ?? null)) {
        $existingAliases = $decodedAliases['aliases'];
    }
}

$aliases = [];
foreach ($existingAliases as $alias => $target) {
    if (!isset($knownPackageSet[$target])) {
        continue;
    }
    $aliases[$alias] = $target;
}

foreach ($knownPackages as $packageName) {
    $generatedAlias = str_replace('/', '-', $packageName);
    if (isset($aliases[$generatedAlias]) && $aliases[$generatedAlias] !== $packageName) {
        fwrite(STDERR, "Alias conflict on {$generatedAlias}, keeping existing target {$aliases[$generatedAlias]}.\n");
        continue;
    }
    $aliases[$generatedAlias] = $packageName;
}

ksort($aliases, SORT_STRING);
file_put_contents(
    $aliasesPath,
    json_encode(['aliases' => $aliases], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n"
);

$index = [
    'recipes' => $recipesByPackage,
    'branch' => $existingIndex['branch'] ?? 'main',
    'is_contrib' => $existingIndex['is_contrib'] ?? true,
    '_links' => (function () use ($existingIndex): array {
        $links = is_array($existingIndex['_links'] ?? null) ? $existingIndex['_links'] : [];
        // Flex expects a host/path value here and may prepend the scheme itself.
        $links['repository'] = 'github.com/artack/suissetec_recipes';
        $links['origin_template'] = 'https://github.com/artack/suissetec_recipes/tree/main/src/{package}/{version}';
        $links['recipe_template'] = 'https://api.github.com/repos/artack/suissetec_recipes/contents/build/{package_dotted}.{version}.json?ref=main';
        return $links;
    })(),
];

file_put_contents($indexPath, json_encode($index, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");

echo "Compiled {$compiledCount} recipe version(s).\n";
PHP
