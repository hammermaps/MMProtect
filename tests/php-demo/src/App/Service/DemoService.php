<?php

declare(strict_types=1);

namespace App\Service;

final class DemoService
{
    public function message(): string
    {
        return 'protected project code executed';
    }
}
