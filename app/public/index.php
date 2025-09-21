<?php
declare(strict_types=1);

use GuzzleHttp\Psr7\HttpFactory;
use Laminas\HttpHandlerRunner\Emitter\SapiEmitter;
use League\Route\Router;
use League\Route\Strategy\JsonStrategy;
use Nyholm\Psr7\Factory\Psr17Factory;
use Nyholm\Psr7Server\ServerRequestCreator;
use App\Presentation\Http\Action\DefaultAction;
use App\Presentation\Http\Action\HelloAction;

require_once __DIR__ . '/../vendor/autoload.php';
require_once __DIR__ . '/../src/error_handler.php';

// Composition root
$container = require_once __DIR__ . '/../src/container.php';

// PSR-7/17 request objects
$psr17 = new Psr17Factory();
$creator = new ServerRequestCreator($psr17, $psr17, $psr17, $psr17);
$request = $creator->fromGlobals();

// Strategy with ResponseFactory and DI container
/** @var HttpFactory $responseFactory */
$responseFactory = $container->get(HttpFactory::class);
$strategy = new JsonStrategy($responseFactory);
$strategy->setContainer($container);

// Router
/** @var \League\Route\Router $router */
$router = new Router()->setStrategy($strategy);

// Routes - use invokable action classes
$router->map('GET', '/', DefaultAction::class);
$router->map('GET', '/hello', HelloAction::class);

// PSR-15 handle + emit
$response = $router->handle($request);
new SapiEmitter()->emit($response);
