<?php

declare(strict_types=1);

namespace WorktreeIsolation;

use InvalidArgumentException;
use PDO;
use PDOException;

/**
 * Per-worktree databases: "{base}_wt_{worktree}". The names are derived in
 * bash (stubs/bin/_worktree-lib.sh); PHP only creates the databases.
 */
abstract class WorktreeDatabaseResolver
{
    const MARKER = '_wt_';

    /**
     * Ensure the given database exists, creating it if necessary.
     *
     * @return bool Whether the database was created by this call.
     *
     * @throws InvalidArgumentException
     * @throws PDOException
     */
    public static function ensureExists(string $name, string $host, int $port, string $user, string $password): bool
    {
        if (preg_match('/^[a-z0-9_-]+$/', $name) !== 1) {
            throw new InvalidArgumentException(
                "Database name \"$name\" contains invalid characters. Only lowercase alphanumeric, hyphens and underscores are allowed."
            );
        }

        $dsn = "mysql:host=$host;port=$port";
        $pdo = new PDO($dsn, $user, $password, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        ]);

        $stmt = $pdo->prepare('SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = :name');
        $stmt->execute(['name' => $name]);

        if ($stmt->fetchColumn()) {
            return false;
        }

        try {
            $pdo->exec(sprintf('CREATE DATABASE `%s`', $name));
        } catch (PDOException $e) {
            if (($e->errorInfo[1] ?? null) !== 1007) {
                throw $e;
            }

            return false;
        }

        return true;
    }
}
