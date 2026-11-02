<?php

declare(strict_types=1);

namespace WorktreeIsolation\Console;

use Illuminate\Support\Facades\Process;
use Symfony\Component\Process\Process as SymfonyProcess;

trait RunsStubScript
{
    /**
     * Runs one of the package's bash scripts from the project root,
     * streaming its output.
     *
     * @param  list<string>  $args
     */
    protected function runStub(string $script, array $args, int $timeout, bool $tty = false): int
    {
        $result = Process::path(base_path())
            ->timeout($timeout)
            ->tty($tty && SymfonyProcess::isTtySupported())
            ->run(['bash', self::stubsDir().'/bin/'.$script, ...$args], function (string $type, string $buffer): void {
                $this->output->write($buffer);
            });

        return $result->successful() ? self::SUCCESS : self::FAILURE;
    }

    public static function stubsDir(): string
    {
        return dirname(__DIR__, 2).'/stubs';
    }
}
