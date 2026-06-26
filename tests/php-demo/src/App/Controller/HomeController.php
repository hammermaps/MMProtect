<?php

declare(strict_types=1);

namespace App\Controller;

use App\Service\DemoService;

final class HomeController
{
    public function index(): string
    {
        $service = new DemoService();

        return "MMProtect Demo: " . $service->message() . PHP_EOL;
    }
}
