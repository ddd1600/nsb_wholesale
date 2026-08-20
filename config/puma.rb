# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside this Puma process rather than as a
# separate Render service. One service, one bill, no worker to keep alive -- and
# at roughly one order a day the job load is a few rows an hour.
#
# :async, not the plugin's default :fork. Fork mode starts a second copy of the
# application, and Render's starter plan gives this service 512MB of RAM for a
# Solidus app that is not small. Async mode runs the dispatcher and workers as
# threads in the process that is already booted. It also avoids fork mode's
# monitor, which kills Puma when the job process dies -- a crash-looping worker
# would otherwise take the storefront down with it.
#
# Threads share this process's Active Record pool, which config/database.yml
# sizes accordingly.
#
# This assumes Puma runs in single mode, which it does: no `workers` directive
# here and WEB_CONCURRENCY is unset on Render. Setting WEB_CONCURRENCY would put
# Puma in clustered mode, where this plugin starts the supervisor in the master
# process -- one queue, still correct, but the pool sizing above would then be
# counting the wrong threads. Revisit both together if that ever changes.
#
# Plain ENV[] rather than .present?: Puma evaluates this file before Rails, so
# Active Support's core extensions do not exist here yet. Using them crashes the
# boot with a bare NoMethodError before anything logs why.
if ENV["SOLID_QUEUE_IN_PUMA"] == "true"
  plugin :solid_queue
  solid_queue_mode :async
end

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
