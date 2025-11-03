<?php
declare(strict_types=1);

use Dotenv\Dotenv;
use League\Config\Configuration;
use League\Config\ConfigurationInterface;
use Nette\Schema\Expect;
use Throwable;

return (function (): ConfigurationInterface {
    try {
        $appRoot = dirname(__DIR__);
        $dotenv  = Dotenv::createImmutable($appRoot);
        $dotenv->load();
        $dotenv->required([
            'APP_ENV',
            'APP_TZ',
            'AWS_REGION',
            'DB_HOST',
            'DB_PORT',
            'DB_NAME',
            'DB_SSLMODE',
            'DB_USER',
            'DB_PASSWORD',
            'LOG_LEVEL',
        ])->notEmpty();
        $dotenv->required('DB_PORT')->isInteger();
    } catch (Throwable $exception) {
        if (!str_contains($exception->getMessage(), '.env')) {
            throw $exception;
        }
    }

    $schema = [
        'app' => Expect::structure([
            'env' => Expect::string()->min(1),
        ])->castTo('array'),

        'aws' => Expect::structure([
            'region' => Expect::string()->min(1),
        ])->castTo('array'),

        'db' => Expect::structure([
            'host'     => Expect::string()->min(1),
            'port'     => Expect::int(),
            'name'     => Expect::string()->min(1),
            'sslMode'  => Expect::string()->min(1),
            'user'     => Expect::string()->min(1),
            'password' => Expect::string()->min(1),
            'dsn'      => Expect::string()->min(1),
        ])->castTo('array'),

        'logger' => Expect::structure([
            'level'    => Expect::anyOf('debug', 'info', 'notice', 'warning', 'error', 'critical', 'alert', 'emergency'),
            'timezone' => Expect::string()->min(1),
        ])->castTo('array'),
    ];

    $config = new Configuration($schema);

    $config->merge([
        'app' => [
            'env' => (string)($_ENV['APP_ENV'] ?? ''),
        ],
        'aws' => [
            'region' => (string)($_ENV['AWS_REGION'] ?? ''),
        ],
        'db' => [
            'host'     => (string)($_ENV['DB_HOST'] ?? ''),
            'port'     => (int)($_ENV['DB_PORT'] ?? 5432),
            'name'     => (string)($_ENV['DB_NAME'] ?? ''),
            'sslMode'  => (string)($_ENV['DB_SSLMODE'] ?? ''),
            'user'     => (string)($_ENV['DB_USER'] ?? ''),
            'password' => (string)($_ENV['DB_PASSWORD'] ?? ''),
        ],
        'logger' => [
            'level'    => (string)($_ENV['LOG_LEVEL'] ?? 'info'),
            'timezone' => (string)($_ENV['APP_TZ'] ?? 'UTC'),
        ],
    ]);

    $dsn = sprintf(
        'pgsql:host=%s;port=%d;dbname=%s;sslmode=%s;connect_timeout=5;application_name=aws-php-lambda',
        (string)$config->get('db.host'),
        (int)$config->get('db.port'),
        (string)$config->get('db.name'),
        (string)$config->get('db.sslMode'),
    );

    $config->merge([
        'db' => [
            'dsn' => $dsn,
        ],
    ]);

    $config->get('app');
    $config->get('aws');
    $config->get('db');
    $config->get('logger');

    return $config;
})();
