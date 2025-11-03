<?php
declare(strict_types=1);

namespace App\Presentation\Http\Action;

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

        // Resolve client IP from headers/server params
        $xff      = $request->getHeaderLine('X-Forwarded-For');
        $clientIp = $xff !== '' ? trim(explode(',', $xff)[0]) : ($request->getServerParams()['REMOTE_ADDR'] ?? null);

        $region = (string)$this->config->get('aws.region');
        $env    = (string)$this->config->get('app.env');

        $meta = [
            'time'   => (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format('Y-m-d\\TH:i:s.vP'),
            'region' => $region,
            'env'    => $env,
            'ip'     => $clientIp,
            'path'   => $request->getUri()->getPath(),
        ];

        try {
            $dsn = (string)$this->config->get('db.dsn');
            $user = (string)$this->config->get('db.user');
            $pass = (string)$this->config->get('db.password');

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
        } catch (\PDOException $e) {
            $this->logger->error('DB error', ['code' => $e->getCode(), 'msg' => $e->getMessage()]);
            return [
                'ok' => false,
                'error' => 'DB connection/query failed',
                'meta' => $meta,
            ];
        } catch (\Throwable $e) {
            $this->logger->error('Unhandled error', ['msg' => $e->getMessage()]);
            return ['ok' => false, 'error' => 'Unhandled error', 'meta' => $meta];
        }
    }
}
