<?php

declare(strict_types=1);

return [

    /*
    |--------------------------------------------------------------------------
    | Docker Image
    |--------------------------------------------------------------------------
    |
    | The Sail Docker image used to run composer install, npm install, and tests
    | inside worktrees. This should match the image built by your project's
    | docker-compose.yml (typically sail-8.x/app).
    |
    */

    'docker_image' => env('WORKTREE_DOCKER_IMAGE', 'sail-8.4/app'),

    /*
    |--------------------------------------------------------------------------
    | Docker Network
    |--------------------------------------------------------------------------
    |
    | The Docker network your Sail services run on. By default, Sail creates a
    | network named "{project-directory}_sail". Set this to match your project.
    |
    */

    'docker_network' => env('WORKTREE_DOCKER_NETWORK', 'laravel_sail'),

    /*
    |--------------------------------------------------------------------------
    | Testing Environment File
    |--------------------------------------------------------------------------
    |
    | The name of the testing environment file to copy into worktrees.
    |
    */

    'testing_env_file' => '.env.testing',

    /*
    |--------------------------------------------------------------------------
    | Testing Environment Example File
    |--------------------------------------------------------------------------
    |
    | Fallback file to copy when the testing env file doesn't exist in the
    | main repo.
    |
    */

    'testing_env_example_file' => '.env.testing.example',

    /*
    |--------------------------------------------------------------------------
    | Per-Worktree Database Flag
    |--------------------------------------------------------------------------
    |
    | The environment variable name that enables per-worktree database isolation.
    | When enabled, each worktree gets its own test database derived from the
    | worktree directory name.
    |
    */

    'db_per_worktree_env_key' => 'TEST_DB_PER_WORKTREE',

    /*
    |--------------------------------------------------------------------------
    | Base Test Database
    |--------------------------------------------------------------------------
    |
    | The base database name used when deriving per-worktree database names.
    | The worktree database will be named: "{base}-{worktree-basename}".
    |
    */

    'base_test_database' => env('DB_DATABASE', 'testing'),

    /*
    |--------------------------------------------------------------------------
    | Environment Variables Passed to Test Container
    |--------------------------------------------------------------------------
    |
    | These environment variable names are read from .env.testing and forwarded
    | to the Docker container when running tests via bin/test.
    |
    */

    'test_env_vars' => [
        'APP_ENV',
        'APP_KEY',
        'APP_DEBUG',
        'DB_CONNECTION',
        'DB_HOST',
        'DB_PORT',
        'DB_DATABASE',
        'DB_USERNAME',
        'DB_PASSWORD',
        'DB_SSL_VERIFY_SERVER_CERT',
        'BCRYPT_ROUNDS',
        'CACHE_DRIVER',
        'MAIL_MAILER',
        'QUEUE_CONNECTION',
        'SESSION_DRIVER',
        'TELESCOPE_ENABLED',
        'TEST_DB_PER_WORKTREE',
    ],

];
