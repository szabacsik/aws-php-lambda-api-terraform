<?php
ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', 'php://stderr');
error_reporting(E_ALL);

function exception_handler(Throwable $exception): void
{
    $statusCode = 500;
    $data['exception'] = [
        'class' => get_class($exception),
        'message' => $exception->getMessage(),
        'file' => $exception->getFile(),
        'line' => $exception->getLine(),
        'code' => $exception->getCode(),
        'trace' => explode("\n", $exception->getTraceAsString()),
    ];
    $data['statusCode'] = $statusCode;
    $entry = sprintf(
        "[app] [php-exception-handler] [host: %s] %s\n",
        gethostname(),
        json_encode($data, JSON_UNESCAPED_UNICODE)
    );
    error_log($entry); //this message is sent to PHP's system logger depending on the error_log configuration in my.ini
    if (php_sapi_name() !== 'cli') {
        header('Content-type: application/json; charset=utf-8');
        http_response_code($statusCode);
    }
    echo(json_encode($data, JSON_PRETTY_PRINT));
}

set_exception_handler('exception_handler');

/**
 * @throws ErrorException
 */
function error_handler($errorNumber, $message, $filePath, $lineNumber)
{
    throw new ErrorException($message, 0, $errorNumber, $filePath, $lineNumber);
}

set_error_handler('error_handler');

function shutdown(): void
{
    $error = error_get_last();
    if ($error !== null) {
        $entry = sprintf(
            "[app] [php-shutdown] [host: %s] %s in %s on line %d\n",
            gethostname(),
            $error['message'],
            $error['file'],
            $error['line']
        );
        error_log($entry); //this message is sent to PHP's system logger depending on the error_log configuration in my.ini
        if (php_sapi_name() !== 'cli') {
            if (!headers_sent()) {
                header('Content-type: application/json; charset=utf-8');
            }
            http_response_code(500);
            $data['exception'] = [
                'message' => $error['message'],
                'file' => $error['file'],
                'line' => $error['line'],
                'statusCode' => 500,
            ];
            echo(json_encode($data, JSON_PRETTY_PRINT));
        }
    }
}

register_shutdown_function('shutdown');
