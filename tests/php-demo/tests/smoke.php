<?php

declare(strict_types=1);

require __DIR__ . '/../vendor/autoload.php';

$app = new App\Application();
$output = $app->run();

if (!str_contains($output, 'protected project code executed')) {
    fwrite(STDERR, "Smoke test failed\n");
    exit(1);
}

echo "Smoke test ok\n";
