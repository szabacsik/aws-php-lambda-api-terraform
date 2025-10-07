<?php
declare(strict_types=1);

namespace App\Presentation\Http\Action;

use Aws\SecretsManager\SecretsManagerClient;
use Aws\Exception\AwsException;
use DateTimeImmutable;
use DateTimeZone;
use League\Config\ConfigurationInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Log\LoggerInterface;

final readonly class DefaultAction
{
    public function __construct(
        private LoggerInterface $logger,
        private ConfigurationInterface $config,
    ) {}

    public function __invoke(ServerRequestInterface $request): array
    {
        $this->logger->info('DefaultAction invoked');

        $region    = getenv('AWS_REGION') ?: 'eu-central-1';
        $dbHost    = getenv('DB_HOST') ?: '';
        $dbPort    = (int) (getenv('DB_PORT') ?: 5432);
        $dbName    = getenv('DB_NAME') ?: '';
        $secretArn = getenv('DB_SECRET_ARN') ?: '';

        $xff      = $request->getHeaderLine('X-Forwarded-For');
        $clientIp = $xff !== '' ? trim(explode(',', $xff)[0]) : ($request->getServerParams()['REMOTE_ADDR'] ?? null);

        $meta = [
            'time'   => (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format('Y-m-d\\TH:i:s.vP'),
            'region' => (string) ($this->config->get('aws.region') ?? $region),
            'env'    => (string) ($this->config->get('app.env') ?? ''),
            'ip'     => $clientIp,
            'path'   => $request->getUri()->getPath(),
        ];

        if ($dbHost === '' || $dbName === '' || $secretArn === '') {
            return [
                'ok'    => false,
                'error' => 'Missing DB env vars (DB_HOST/DB_NAME/DB_SECRET_ARN).',
                'meta'  => $meta,
            ];
        }

        try {
            // 1) Secrets Manager
            $secretsManagerEndpoint = getenv('AWS_SM_ENDPOINT') ?: null;
            $secretsManagerConfig = [
                'version' => '2017-10-17',
                'region'  => $region,
                'http'    => [
                    'connect_timeout' => 1.0,
                    'timeout'         => 3.0,
                ],
            ];
            if ($secretsManagerEndpoint) {
                // Route to LocalStack in local dev and use static dummy credentials
                $secretsManagerConfig['endpoint'] = $secretsManagerEndpoint;
                $secretsManagerConfig['credentials'] = [
                    'key'    => getenv('AWS_ACCESS_KEY_ID') ?: 'test',
                    'secret' => getenv('AWS_SECRET_ACCESS_KEY') ?: 'test',
                ];
            }
            $secretsManagerClient  = new SecretsManagerClient($secretsManagerConfig);
            $result = $secretsManagerClient->getSecretValue(['SecretId' => $secretArn]);

            $secretString = $result['SecretString'] ?? null;
            if ($secretString === null && isset($result['SecretBinary'])) {
                $secretString = base64_decode($result['SecretBinary']);
            }
            $payload = json_decode($secretString ?? '{}', true, 512, JSON_THROW_ON_ERROR);

            $user = $payload['username'] ?? null;
            $pass = $payload['password'] ?? null;

            if (!$user || !$pass) {
                return ['ok' => false, 'error' => 'Secret is missing "username" or "password".', 'meta' => $meta];
            }

            // 2) PDO + TLS + sane timeouts/metadata
            $dbSSLMode = getenv('DB_SSLMODE') ?: 'require'; // disable
            $dsn = sprintf(
                "pgsql:host=%s;port=%d;dbname=%s;sslmode=%s;connect_timeout=5;application_name=aws-php-lambda",
                $dbHost,
                $dbPort,
                $dbName,
                $dbSSLMode,
            );

            $pdo = new \PDO($dsn, $user, $pass, [
                \PDO::ATTR_ERRMODE            => \PDO::ERRMODE_EXCEPTION,
                \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
                \PDO::ATTR_EMULATE_PREPARES   => false,
            ]);

            $utcNow        = $pdo->query("SELECT now() AT TIME ZONE 'UTC' AS utc_now")->fetchColumn();
            $serverVersion = $pdo->query("SHOW server_version")->fetchColumn();

            return [
                'ok'   => true,
                'db'   => [
                    'utc_now'        => $utcNow,
                    'server_version' => $serverVersion,
                ],
                'meta' => $meta,
            ];
        } catch (AwsException $e) {
            $this->logger->error('Secrets Manager error', ['code' => $e->getAwsErrorCode(), 'msg' => $e->getMessage()]);
            return ['ok' => false, 'error' => 'Secret retrieval failed', 'meta' => $meta];
        } catch (\PDOException $e) {
            $this->logger->error('DB error', ['code' => $e->getCode(), 'msg' => $e->getMessage()]);
            return ['ok' => false, 'error' => 'DB connection/query failed', 'meta' => $meta];
        } catch (\Throwable $e) {
            $this->logger->error('Unhandled error', ['msg' => $e->getMessage()]);
            return ['ok' => false, 'error' => 'Unhandled error', 'meta' => $meta, 'e' => (string)$e, 'arn' => $secretArn];
        }
    }
}
