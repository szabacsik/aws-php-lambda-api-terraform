<?php
declare(strict_types=1);

// Single-file, framework-free Lambda PHP API using only Monolog for logging.
// Works behind API Gateway HTTP API via Bref's PHP-FPM layer.

require __DIR__ . '/../vendor/autoload.php';

use Monolog\Formatter\JsonFormatter;
use Monolog\Handler\StreamHandler;
use Monolog\Level;
use Monolog\Logger;

$start = microtime(true);

// Set timezone for Monolog and PHP date functions
@date_default_timezone_set('Europe/Budapest');

// Configure logger to write JSON lines to stderr (collected by CloudWatch Logs)
$logger = new Logger('app');
$handler = new StreamHandler('php://stderr', Level::Info);
$handler->setFormatter(new JsonFormatter());
$logger->pushHandler($handler);


// Helper to fetch headers from $_SERVER
$headers = [];
foreach ($_SERVER as $k => $v) {
    if (str_starts_with($k, 'HTTP_')) {
        $name = str_replace('_', '-', strtolower(substr($k, 5)));
        $headers[$name] = $v;
    }
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path   = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

$logger->info('Incoming request', [
    'method'      => $method,
    'path'        => $path,
    'query'       => $_GET ?? [],
    'headers'     => $headers,
]);

$status = 200;
$payload = null;

try {
    if ($method === 'GET' && $path === '/') {
        $payload = [
            'status'     => 'ok',
            'message'    => 'AWS Lambda PHP API skeleton (Terraform + Bref, single-file)',
            'time'       => gmdate('c'),
            'region'     => getenv('AWS_REGION') ?: 'unknown',
            'env'        => getenv('APP_ENV') ?: 'unknown',
            'ip'         => $_SERVER['REMOTE_ADDR'] ?? null,
            'path'       => $path,
        ];
    } elseif ($method === 'GET' && $path === '/hello') {
        $payload = [
            'status'     => 'ok',
            'message'    => 'hello',
            'time'       => gmdate('c'),
        ];
    } else {
        $status = 404;
        $payload = [
            'status'     => 'error',
            'error'      => 'Not Found',
            'path'       => $path,
        ];
    }
} catch (Throwable $e) {
    $status = 500;
    $payload = [
        'status'     => 'error',
        'error'      => 'Internal Server Error',
    ];
    $logger->error('Unhandled exception', ['exception' => [
        'type'    => get_class($e),
        'message' => $e->getMessage(),
    ]]);
}

http_response_code($status);
header('Content-Type: application/json');
echo json_encode($payload, JSON_UNESCAPED_SLASHES);

$logger->info('Response sent', [
    'status'      => $status,
    'duration_ms' => (int) ((microtime(true) - $start) * 1000),
]);
