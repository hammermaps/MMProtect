<?php

declare(strict_types=1);

namespace App;

use App\Controller\HomeController;

final class Application
{
    public function run(): string
    {
        $controller = new HomeController();
        return $controller->index();
    }
}
