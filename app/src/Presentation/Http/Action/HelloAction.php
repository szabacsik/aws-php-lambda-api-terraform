<?php
declare(strict_types=1);

namespace App\Presentation\Http\Action;

use Psr\Log\LoggerInterface;

final readonly class HelloAction
{
    public function __construct(private LoggerInterface $logger)
    {
    }

    public function __invoke(): array
    {
        $this->logger->info('HelloAction invoked');
        return ['message' => 'hello', 'ts' => time()];
    }
}
