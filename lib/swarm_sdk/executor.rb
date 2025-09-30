# frozen_string_literal: true

module SwarmSDK
  class Executor
    def initialize(max_concurrent: nil)
      @semaphore = max_concurrent ? Async::Semaphore.new(max_concurrent) : nil
    end

    def execute_async(agent, input)
      Async do
        if @semaphore
          @semaphore.acquire do
            agent.execute(input)
          end
        else
          agent.execute(input)
        end
      end
    end

    def execute_sync(agent, input)
      Async do
        if @semaphore
          @semaphore.acquire do
            agent.execute(input)
          end
        else
          agent.execute(input)
        end
      end.wait
    end

    def execute_all(agents, input)
      Async do
        tasks = agents.map do |agent|
          Async do
            if @semaphore
              @semaphore.acquire do
                agent.execute(input)
              end
            else
              agent.execute(input)
            end
          end
        end

        tasks.map(&:wait)
      end.wait
    end
  end
end
