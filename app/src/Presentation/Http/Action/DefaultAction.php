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
    ) {
    }

    /**
     * @throws \DateMalformedStringException
     */
    public function __invoke(ServerRequestInterface $request): array
    {
        $this->logger->info('DefaultAction invoked', ['lorem' => 'ipsum']);

        return [
            'status' => 'ok',
            'message' => 'AWS Lambda PHP API skeleton (Terraform + Bref)',
            'time' => new DateTimeImmutable('now', new DateTimeZone('UTC'))->format('Y-m-d\\TH:i:s.vP'),
            'region' => (string)$this->config->get('aws.region'),
            'env' => (string)$this->config->get('app.env'),
            'ip' => $request->getServerParams()['REMOTE_ADDR'] ?? null,
            'path' => $request->getUri()->getPath(),
        ];
    }
}
