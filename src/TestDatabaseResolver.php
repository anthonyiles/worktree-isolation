<?php

declare(strict_types=1);

namespace WorktreeIsolation;

use InvalidArgumentException;
use PDO;
use PDOException;

class TestDatabaseResolver
{
    const int MAX_DERIVED_LENGTH = 40;

    /**
     * Derive a per-worktree test database name from the base name and worktree directory.
     *
     * @throws InvalidArgumentException
     */
    public static function derive(string $base, string $worktreeBasename): string
    {
        $suffix = strtolower($worktreeBasename);
        $suffix = preg_replace('/[^a-z0-9]+/', '-', $suffix) ?? '';
        $suffix = trim($suffix, '-');

        if ($suffix === '') {
            $suffix = 'worktree';
        }

        $derived = "$base-$suffix";

        if (! str_contains(strtolower($derived), 'test')) {
            throw new InvalidArgumentException(
                "Derived database name \"$derived\" does not contain \"test\". Refusing to proceed — this guard prevents accidental use of a non-test database."
            );
        }

        if (strlen($derived) > self::MAX_DERIVED_LENGTH) {
            throw new InvalidArgumentException(
                "Derived database name \"$derived\" exceeds the maximum length of ".self::MAX_DERIVED_LENGTH.' characters. Shorten your worktree directory name.'
            );
        }

        return $derived;
    }

    /**
     * Ensure the given database exists, creating it if necessary.
     *
     * @throws InvalidArgumentException
     * @throws PDOException
     */
    public static function ensureExists(string $name, string $host, int $port, string $user, string $password): void
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
            return;
        }

        try {
            $pdo->exec(sprintf('CREATE DATABASE `%s`', $name));
        } catch (PDOException $e) {
            if (($e->errorInfo[1] ?? null) !== 1007) {
                throw $e;
            }
        }
    }
}
