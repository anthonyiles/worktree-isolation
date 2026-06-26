<?php

declare(strict_types=1);

return [

    /*
    |--------------------------------------------------------------------------
    | Runtime Driver
    |--------------------------------------------------------------------------
    |
    | How commands (composer install, npm install, test runner) are executed.
    |
    | Supported: "native", "docker-compose", "docker-image"
    |
    |   native         — run directly on the host (Herd, Valet, any local PHP)
    |   docker-compose — run via `docker compose exec` in a running service
    |   docker-image   — run via `docker run` with a standalone Docker image
    |
    */

    'runtime' => env('WORKTREE_RUNTIME', 'native'),

    /*
    |--------------------------------------------------------------------------
    | Docker Compose Service
    |--------------------------------------------------------------------------
    |
    | The service name used with `docker compose exec` when the runtime is
    | "docker-compose". This should match a service in your docker-compose.yml.
    |
    */

    'compose_service' => env('WORKTREE_COMPOSE_SERVICE', 'app'),

    /*
    |--------------------------------------------------------------------------
    | Docker Compose File
    |--------------------------------------------------------------------------
    |
    | Optional path to your docker-compose file, relative to the project root.
    | Only used with the "docker-compose" runtime. Leave empty to use the
    | default docker-compose.yml.
    |
    */

    'compose_file' => env('WORKTREE_COMPOSE_FILE', ''),

    /*
    |--------------------------------------------------------------------------
    | Docker Image
    |--------------------------------------------------------------------------
    |
    | The Docker image used to run commands when the runtime is "docker-image".
    | This is typically the image built by your docker-compose.yml or Sail.
    |
    */

    'docker_image' => env('WORKTREE_DOCKER_IMAGE', ''),

    /*
    |--------------------------------------------------------------------------
    | Docker Network
    |--------------------------------------------------------------------------
    |
    | The Docker network to attach ephemeral containers to when the runtime is
    | "docker-image". This allows the test container to reach your database
    | and other services.
    |
    */

    'docker_network' => env('WORKTREE_DOCKER_NETWORK', ''),

    /*
    |--------------------------------------------------------------------------
    | Docker Working Directory
    |--------------------------------------------------------------------------
    |
    | The working directory inside the Docker container where the project is
    | mounted. Only used with the "docker-image" runtime.
    |
    */

    'docker_workdir' => env('WORKTREE_DOCKER_WORKDIR', '/var/www/html'),

    /*
    |--------------------------------------------------------------------------
    | Test Command
    |--------------------------------------------------------------------------
    |
    | The command used to run tests. Defaults to `php artisan test` for Laravel
    | projects. Non-Laravel projects can set this to `php vendor/bin/phpunit`,
    | `./vendor/bin/pest`, or any other test runner.
    |
    */

    'test_command' => env('WORKTREE_TEST_COMMAND', 'php artisan test'),

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
    | to the Docker container when running tests via bin/test. Only relevant
    | for the "docker-image" runtime.
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
