<?php
declare(strict_types=1);

use Dotenv\Dotenv;
use League\Config\Configuration;
use League\Config\ConfigurationInterface;
use Nette\Schema\Expect;

return (function (): ConfigurationInterface {
    try {
        $appRoot = dirname(__DIR__);
        $dotenv = Dotenv::createImmutable($appRoot);
        $dotenv->load();
    } catch (Throwable $exception) {
        if (!str_contains($exception->getMessage(), '.env')) {
            throw $exception;
        }
    }

    $schema = [
        'app' => Expect::structure([
            'env' => Expect::string()->default('production'),
        ])->castTo('array'),

        'aws' => Expect::structure([
            'region' => Expect::string()->default('unknown'),
        ])->castTo('array'),

        'logger' => Expect::structure([
            'level' => Expect::anyOf('debug', 'info', 'notice', 'warning', 'error', 'critical', 'alert', 'emergency')->default('info'),
            'timezone' => Expect::string()->default('Europe/Budapest'),
        ])->castTo('array'),
    ];

    $config = new Configuration($schema);

    $config->merge([
        'app' => [
            'env' => $_ENV['APP_ENV'] ?? getenv('APP_ENV') ?: 'unknown',
        ],
        'aws' => [
            'region' => $_ENV['AWS_REGION'] ?? getenv('AWS_REGION') ?: 'unknown',
        ],
        'logger' => [
            'level' => $_ENV['LOG_LEVEL'] ?? getenv('LOG_LEVEL') ?: 'info',
            'timezone' => $_ENV['APP_TZ'] ?? getenv('APP_TZ') ?: 'Europe/Budapest',
        ],
    ]);

    return $config;
})();
