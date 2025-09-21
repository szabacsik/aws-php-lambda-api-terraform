<?php
declare(strict_types=1);

use Bref\Monolog\CloudWatchFormatter;
use League\Container\Container;
use Psr\Container\ContainerInterface;
use GuzzleHttp\Psr7\HttpFactory;
use Monolog\Logger;
use Monolog\Handler\StreamHandler;
use Monolog\Level;
use App\Presentation\Http\Action\DefaultAction;
use App\Presentation\Http\Action\HelloAction;
use League\Config\ConfigurationInterface;

return (function (): ContainerInterface {
    $container = new Container();

    // PSR-17 ResponseFactory
    $container->addShared(HttpFactory::class, fn() => new HttpFactory());

    // Configuration
    /** @var ConfigurationInterface $configuration */
    $configuration = require __DIR__ . '/configuration.php';
    $container->addShared(ConfigurationInterface::class, $configuration);

    // Logger
    $container->addShared(Logger::class, function () use ($container) {
        /** @var ConfigurationInterface $config */
        $config = $container->get(ConfigurationInterface::class);

        $timezone = (string)$config->get('logger.timezone');
        @date_default_timezone_set($timezone);

        $level = match (strtolower((string)$config->get('logger.level'))) {
            'debug' => Level::Debug,
            'notice' => Level::Notice,
            'warning' => Level::Warning,
            'error' => Level::Error,
            'critical' => Level::Critical,
            'alert' => Level::Alert,
            'emergency' => Level::Emergency,
            default => Level::Info,
        };

        $logger = new Logger('app');
        $logger->setTimezone(new DateTimeZone($timezone));
        $logger->useMicrosecondTimestamps(true);

        $handler = new StreamHandler('php://stderr', $level);
        $handler->setFormatter(new CloudWatchFormatter());
        $logger->pushHandler($handler);

        return $logger;
    });

    // Domain Actions
    $container->addShared(DefaultAction::class)
      ->addArgument(Logger::class)
      ->addArgument(ConfigurationInterface::class);
    $container->addShared(HelloAction::class)
      ->addArgument(Logger::class);

    return $container;
})();
