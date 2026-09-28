# frozen_string_literal: true

require_relative 'retry'

RSpec.describe Retry do
  class TransientError < StandardError; end
  class FatalError < StandardError; end

  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:strategy) { :constant }
  let(:max_attempts) { 4 }
  let(:retry_on) { [TransientError] }

  subject(:retrier) do
    described_class.new(
      max_attempts: max_attempts,
      strategy: strategy,
      base_delay: 1.0,
      retry_on: retry_on,
      sleeper: sleeper
    )
  end

  def flaky(failures, error: TransientError)
    calls = 0
    fn = lambda do
      calls += 1
      raise error, "fail ##{calls}" if calls <= failures

      :ok
    end
    [fn, -> { calls }]
  end

  describe 'success' do
    it 'returns the result on the first attempt without sleeping' do
      fn, calls = flaky(0)

      expect(retrier.execute(fn)).to eq(:ok)
      expect(calls.call).to eq(1)
      expect(sleeps).to be_empty
    end

    it 'returns the result after n-th attempt' do
      fn, calls = flaky(2)

      expect(retrier.execute(fn)).to eq(:ok)
      expect(calls.call).to eq(3)
      expect(sleeps.size).to eq(2)
    end

    it 'succeeds on the very last allowed attempt' do
      fn, calls = flaky(max_attempts - 1)

      expect(retrier.execute(fn)).to eq(:ok)
      expect(calls.call).to eq(max_attempts)
    end
  end

  describe 'exhausting attempts' do
    it 'stops after maxAttempts and raises the last error' do
      fn, calls = flaky(100)

      expect { retrier.execute(fn) }.to raise_error(TransientError, "fail ##{max_attempts}")
      expect(calls.call).to eq(max_attempts)
    end

    it 'does not sleep after the last attempt' do
      fn, = flaky(100)
      retrier.execute(fn) rescue nil

      expect(sleeps.size).to eq(max_attempts - 1)
    end

    it 'constant: total delay = (maxAttempts - 1) * base' do
      fn, = flaky(100)
      retrier.execute(fn) rescue nil

      expect(sleeps).to eq([1.0, 1.0, 1.0])
      expect(sleeps.sum).to eq(3.0)
    end

    context 'with exponential strategy' do
      let(:strategy) { :exponential }

      it 'doubles the delay every attempt; total = 1 + 2 + 4' do
        fn, = flaky(100)
        retrier.execute(fn) rescue nil

        expect(sleeps).to eq([1.0, 2.0, 4.0])
        expect(sleeps.sum).to eq(7.0)
      end
    end

    context 'with exponential_jitter strategy' do
      let(:strategy) { :exponential_jitter }

      it 'scales the exponential delay by the random factor' do
        random = double('random', rand: 0.5)
        jittered = described_class.new(
          max_attempts: 4, strategy: :exponential_jitter, base_delay: 1.0,
          retry_on: [TransientError], sleeper: sleeper, random: random
        )
        fn, = flaky(100)
        jittered.execute(fn) rescue nil

        expect(sleeps).to eq([0.5, 1.0, 2.0])
      end

      it 'keeps every delay within [0, exponential cap]' do
        fn, = flaky(100)
        retrier.execute(fn) rescue nil

        sleeps.each_with_index do |delay, i|
          expect(delay).to be_between(0, 2**i * 1.0)
        end
      end
    end
  end

  describe 'non-retryable errors' do
    it 'raises immediately without retrying or sleeping' do
      fn, calls = flaky(1, error: FatalError)

      expect { retrier.execute(fn) }.to raise_error(FatalError)
      expect(calls.call).to eq(1)
      expect(sleeps).to be_empty
    end

    it 'stops retrying as soon as a non-retryable error appears mid-way' do
      attempts = 0
      fn = lambda do
        attempts += 1
        raise(attempts == 1 ? TransientError : FatalError)
      end

      expect { retrier.execute(fn) }.to raise_error(FatalError)
      expect(attempts).to eq(2)
      expect(sleeps.size).to eq(1)
    end
  end

  describe 'retry_on' do
    it 'retries subclasses of the listed errors' do
      sub = Class.new(TransientError)
      fn, calls = flaky(1, error: sub)

      expect(retrier.execute(fn)).to eq(:ok)
      expect(calls.call).to eq(2)
    end

    context 'with a predicate (e.g. error codes)' do
      let(:retry_on) { [->(e) { e.message.start_with?('503') }] }

      it 'retries when the predicate matches' do
        calls = 0
        fn = -> { (calls += 1) < 3 ? raise('503 unavailable') : :ok }

        expect(retrier.execute(fn)).to eq(:ok)
        expect(calls).to eq(3)
      end

      it 'does not retry when the predicate does not match' do
        calls = 0
        fn = -> { calls += 1; raise '400 bad request' }

        expect { retrier.execute(fn) }.to raise_error('400 bad request')
        expect(calls).to eq(1)
      end
    end
  end

  describe 'edge cases' do
    it 'maxAttempts = 1 means no retries' do
      single = described_class.new(max_attempts: 1, retry_on: [TransientError], sleeper: sleeper)
      fn, calls = flaky(100)

      expect { single.execute(fn) }.to raise_error(TransientError)
      expect(calls.call).to eq(1)
      expect(sleeps).to be_empty
    end

    context 'with an unknown strategy' do
      let(:strategy) { :fibonacci }

      it 'raises ArgumentError when a delay is needed' do
        fn, = flaky(1)
        expect { retrier.execute(fn) }.to raise_error(ArgumentError, /unknown strategy/)
      end
    end
  end
end
