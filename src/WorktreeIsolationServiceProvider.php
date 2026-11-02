<?php

declare(strict_types=1);

namespace WorktreeIsolation;

use Illuminate\Support\ServiceProvider;
use WorktreeIsolation\Console\CleanDatabasesCommand;
use WorktreeIsolation\Console\InstallCommand;

class WorktreeIsolationServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            $this->commands([
                InstallCommand::class,
                CleanDatabasesCommand::class,
            ]);
        }
    }
}
