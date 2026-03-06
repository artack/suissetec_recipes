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

/**
 * Build a deterministic 40-char recipe ref from manifest + files.
 * This changes only when recipe content changes.
 */
function buildRecipeRef(string $package, string $version, array $manifest, array $files): string
{
    $payload = [
        'package' => $package,
        'version' => $version,
        'manifest' => $manifest,
        'files' => $files,
    ];

    $json = json_encode($payload, JSON_UNESCAPED_SLASHES);
    if (!is_string($json)) {
        throw new RuntimeException('Unable to encode recipe payload for ref generation.');
    }

    return sha1($json);
}

$indexPath = $root . '/index.json';
$aliasesPath = $root . '/aliases.json';
$buildDir = $root . '/build';
$existingIndex = [];
if (is_file($indexPath)) {
    $decoded = json_decode((string) file_get_contents($indexPath), true);
    if (is_array($decoded)) {
        $existingIndex = $decoded;
    }
}

$branch = $existingIndex['branch'] ?? 'main';

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

$excludedRootDirs = [
    '.git' => true,
    '.github' => true,
    '.idea' => true,
    'build' => true,
];

$vendorDirs = glob($root . '/*', GLOB_ONLYDIR);
if ($vendorDirs === false) {
    fwrite(STDERR, "Unable to scan repository.\n");
    exit(1);
}

sort($vendorDirs, SORT_STRING);

foreach ($vendorDirs as $vendorDir) {
    $vendor = basename($vendorDir);
    if (isset($excludedRootDirs[$vendor])) {
        continue;
    }

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
                        'ref' => buildRecipeRef($fullPackage, $version, $manifest, $files),
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
    fwrite(STDERR, "No recipes found. Expected directories like vendor/package/version/manifest.json\n");
    exit(1);
}

ksort($recipesByPackage, SORT_STRING);
foreach ($recipesByPackage as &$versions) {
    usort($versions, static function (string $a, string $b): int {
        $cmp = version_compare($a, $b);
        return $cmp !== 0 ? $cmp : strcmp($a, $b);
    });
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
    'branch' => $branch,
    'is_contrib' => $existingIndex['is_contrib'] ?? true,
    '_links' => (function () use ($existingIndex, $branch): array {
        $links = is_array($existingIndex['_links'] ?? null) ? $existingIndex['_links'] : [];
        // Flex expects a host/path value here and may prepend the scheme itself.
        $links['repository'] = 'github.com/artack/suissetec_recipes';
        $links['origin_template'] = sprintf('{package}:{version}@github.com/artack/suissetec_recipes:%s', $branch);
        $links['recipe_template'] = sprintf(
            'https://api.github.com/repos/artack/suissetec_recipes/contents/build/{package_dotted}.{version}.json?ref=%s',
            $branch
        );
        return $links;
    })(),
];

file_put_contents($indexPath, json_encode($index, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");

echo "Compiled {$compiledCount} recipe version(s).\n";
PHP
