<?php

declare(strict_types=1);

namespace WorktreeIsolation;

use Illuminate\Support\ServiceProvider;
use WorktreeIsolation\Console\InstallCommand;

class WorktreeIsolationServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->mergeConfigFrom(__DIR__.'/../config/worktree-isolation.php', 'worktree-isolation');
    }

    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            $this->publishes([
                __DIR__.'/../config/worktree-isolation.php' => config_path('worktree-isolation.php'),
            ], 'worktree-isolation-config');

            $this->commands([
                InstallCommand::class,
            ]);
        }
    }
}
