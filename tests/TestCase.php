<?php

declare(strict_types=1);

namespace WorktreeIsolation\Tests;

use Orchestra\Testbench\TestCase as BaseTestCase;
use WorktreeIsolation\WorktreeIsolationServiceProvider;

abstract class TestCase extends BaseTestCase
{
    protected function getPackageProviders($app): array
    {
        return [WorktreeIsolationServiceProvider::class];
    }
}
