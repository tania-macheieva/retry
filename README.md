# Retry

A Ruby implementation of the **Retry pattern** for automatically re-executing operations that may temporarily fail.

The implementation allows retry behavior to be configured by the maximum number of attempts, delay strategy, and the errors that should trigger a retry.

### How it works

The wrapped function is executed immediately. If it raises a retryable error, the operation is retried until it succeeds or the maximum number of attempts is reached.

Supported delay strategies:

* **Constant** — uses the same delay between every retry.
* **Exponential** — doubles the delay after each failed attempt.
* **Exponential Jitter** — applies a random factor to the exponential delay to reduce synchronized retries when multiple clients retry at the same time.

Only explicitly configured errors or matching predicates are retried. Non-retryable errors are raised immediately.

### Configuration

* `max_attempts` — total number of attempts, including the initial attempt.
* `strategy` — `:constant`, `:exponential`, or `:exponential_jitter`.
* `base_delay` — base delay between attempts in seconds.
* `retry_on` — exception classes and/or predicates that determine which errors are retryable.
* `sleeper` — waiting mechanism, injectable for testing without real delays.
* `random` — randomness source used by the jitter strategy.

### Features

* Configurable maximum number of attempts
* Constant, exponential, and exponential-jitter backoff
* Selective retry based on exception classes
* Support for custom retry predicates
* Injectable sleeper for deterministic tests
* Injectable random generator for deterministic jitter tests
* Raises the last error when all attempts are exhausted

### Tests

The RSpec test suite covers:

* Successful execution without retries
* Successful execution after temporary failures
* Exhausting the maximum number of attempts
* Constant and exponential delay calculation
* Exponential jitter and its bounds
* Non-retryable errors
* Stopping retries when a non-retryable error occurs
* Exception subclasses
* Predicate-based retry conditions
* `max_attempts: 1`
* Invalid retry strategies

The retry logic is separated from sleeping and randomness, making the implementation deterministic and easy to test.
