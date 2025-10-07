<?php
declare(strict_types=1);

use Dotenv\Dotenv;
use League\Config\Configuration;
use League\Config\ConfigurationInterface;
use Nette\Schema\Expect;

return (function (): ConfigurationInterface {
    // Load environment variables from .env if present. Ignore if file missing.
    try {
        $appRoot = dirname(__DIR__);
        $dotenv = Dotenv::createImmutable($appRoot);
        $dotenv->load();
        // Validate required environment variables and types using Dotenv
        $dotenv->required([
            'APP_ENV',
            'APP_TZ',
            'AWS_REGION',
            'AWS_SM_HTTP_CONNECT_TIMEOUT',
            'AWS_SM_HTTP_TIMEOUT',
            'DB_HOST',
            'DB_PORT',
            'DB_NAME',
            'DB_SSLMODE',
            'DB_SECRET_ARN',
            'LOG_LEVEL',
        ])->notEmpty();
        $dotenv->required('DB_PORT')->isInteger();
        $dotenv->required('AWS_SM_HTTP_CONNECT_TIMEOUT')->isInteger();
        $dotenv->required('AWS_SM_HTTP_TIMEOUT')->isInteger();
        if (!empty($_ENV['AWS_SM_ENDPOINT'])) {
            $dotenv->required(['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY'])->notEmpty();
        }
    } catch (Throwable $exception) {
        if (!str_contains($exception->getMessage(), '.env')) {
            throw $exception;
        }
    }

    // Define configuration schema with validation rules
    $schema = [
        'app' => Expect::structure([
            'env' => Expect::string()->min(1),
        ])->castTo('array'),

        'aws' => Expect::structure([
            'region' => Expect::string()->min(1),
            'secretsManager' => Expect::structure([
                'version' => Expect::string()->min(1),
                'endpoint' => Expect::string()->nullable(),
                'http' => Expect::structure([
                    'connect_timeout' => Expect::float(),
                    'timeout' => Expect::float(),
                ])->castTo('array'),
                'credentials' => Expect::structure([
                    'key' => Expect::string()->nullable(),
                    'secret' => Expect::string()->nullable(),
                ])->castTo('array'),
                // Ready-to-use client configuration array for Aws\SecretsManager\SecretsManagerClient
                'clientConfig' => Expect::arrayOf(Expect::mixed()),
            ])->castTo('array'),
        ])->castTo('array'),

        'db' => Expect::structure([
            'host' => Expect::string()->min(1),
            'port' => Expect::int(),
            'name' => Expect::string()->min(1),
            'sslMode' => Expect::string()->min(1),
            'credentials' => Expect::structure([
                'secretArn' => Expect::string()->min(1),
            ])->castTo('array'),
            // The final DSN must be assembled here, not in the action
            'dsn' => Expect::string()->min(1),
        ])->castTo('array'),

        'logger' => Expect::structure([
            'level' => Expect::anyOf('debug', 'info', 'notice', 'warning', 'error', 'critical', 'alert', 'emergency'),
            'timezone' => Expect::string()->min(1),
        ])->castTo('array'),
    ];

    $config = new Configuration($schema);

    // Directly merge environment-driven configuration values without defaults
    $config->merge([
        'app' => [
            'env' => (string)$_ENV['APP_ENV'],
        ],
        'aws' => [
            'region' => (string)$_ENV['AWS_REGION'],
            'secretsManager' => [
                'version' => '2017-10-17',
                'endpoint' => $_ENV['AWS_SM_ENDPOINT'] ?? null,
                'http' => [
                    'connect_timeout' => (float)$_ENV['AWS_SM_HTTP_CONNECT_TIMEOUT'],
                    'timeout' => (float)$_ENV['AWS_SM_HTTP_TIMEOUT'],
                ],
                'credentials' => [
                    'key' => $_ENV['AWS_ACCESS_KEY_ID'] ?? null,
                    'secret' => $_ENV['AWS_SECRET_ACCESS_KEY'] ?? null,
                ],
            ],
        ],
        'db' => [
            'host' => (string)$_ENV['DB_HOST'],
            'port' => (int) $_ENV['DB_PORT'],
            'name' => (string)$_ENV['DB_NAME'],
            'sslMode' => (string)$_ENV['DB_SSLMODE'],
            'credentials' => [
                'secretArn' => (string)$_ENV['DB_SECRET_ARN'],
            ],
        ],
        'logger' => [
            'level' => (string)$_ENV['LOG_LEVEL'],
            'timezone' => (string)$_ENV['APP_TZ'],
        ],
    ]);

    // Compute derived configurations using already merged values

    // AWS Secrets Manager clientConfig
    $smClientConfig = [
        'version' => (string)$config->get('aws.secretsManager.version'),
        'region'  => (string)$config->get('aws.region'),
        'http'    => [
            'connect_timeout' => (float)$config->get('aws.secretsManager.http.connect_timeout'),
            'timeout'         => (float)$config->get('aws.secretsManager.http.timeout'),
        ],
    ];
    $endpoint = $config->get('aws.secretsManager.endpoint');
    if ($endpoint !== null && $endpoint !== '') {
        $smClientConfig['endpoint'] = (string)$endpoint;

        $key = $config->get('aws.secretsManager.credentials.key');
        $secret = $config->get('aws.secretsManager.credentials.secret');

        if ($key !== null && $key !== '' && $secret !== null && $secret !== '') {
            $smClientConfig['credentials'] = [
                'key'    => (string)$key,
                'secret' => (string)$secret,
            ];
        }
    }

    // Database DSN
    $dbHost = (string)$config->get('db.host');
    $dbPort = (int) $config->get('db.port');
    $dbName = (string)$config->get('db.name');
    $dbSslMode = (string)$config->get('db.sslMode');

    $dsn = sprintf(
        'pgsql:host=%s;port=%d;dbname=%s;sslmode=%s;connect_timeout=5;application_name=aws-php-lambda',
        $dbHost,
        $dbPort,
        $dbName,
        $dbSslMode,
    );

    // Merge derived values
    $config->merge([
        'aws' => [
            'secretsManager' => [
                'clientConfig' => $smClientConfig,
            ],
        ],
        'db' => [
            'dsn' => $dsn,
        ],
    ]);

    // Trigger validation early to fail fast on misconfiguration
    $config->get('app');
    $config->get('aws');
    $config->get('db');
    $config->get('logger');

    return $config;
})();
