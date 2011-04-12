module MCollective
    module Agent
        # An agent to manage the Puppet Daemon
        #
        # Configuration Options:
        #    puppetd.splaytime - How long to splay for, no splay by default
        #    puppetd.statefile - Where to find the state.yaml file defaults to
        #                        /var/lib/puppet/state/state.yaml
        #    puppetd.lockfile  - Where to find the lock file defaults to
        #                        /var/lib/puppet/state/puppetdlock
        #    puppetd.puppetd   - Where to find the puppetd, defaults to
        #                        /usr/sbin/puppetd
        #    puppetd.options_whitelist     - Comma seperated list of valid 
        #                        options
        #    puppetd.options_illegal_chars - String comprised of invalid 
        #                        characters in options.
        #    puppetd.options_options_regex - The Regex options must match.
        #
        class Puppetd<RPC::Agent
            metadata    :name        => "SimpleRPC Puppet Agent",
                        :description => "Agent to manage the puppet daemon",
                        :author      => "R.I.Pienaar",
                        :license     => "Apache License 2.0",
                        :version     => "1.3",
                        :url         => "http://mcollective-plugins.googlecode.com/",
                        :timeout     => 20

            def startup_hook
                @splaytime = @config.pluginconf["puppetd.splaytime"].to_i || 0
                @lockfile = @config.pluginconf["puppetd.lockfile"] || "/var/lib/puppet/state/puppetdlock"
                @statefile = @config.pluginconf["puppetd.statefile"] || "/var/lib/puppet/state/state.yaml"
                @pidfile = @config.pluginconf["puppet.pidfile"] || "/var/run/puppet/agent.pid"
                @puppetd = @config.pluginconf["puppetd.puppetd"] || "/usr/sbin/puppetd"
                
                if @config.pluginconf["puppetd.options_whitelist"]
                    @options_whitelist = @config.pluginconf["puppetd.options_whitelist"].split(',')
                else
                    @options_whitelist = ["--noop","--no-noop"]
                end
                if @config.pluginconf["puppetd.options_illegal_chars"]
                    @options_illegal_chars = Regexp.new(@config.pluginconf["puppetd.options_illegal_chars"])
                else
                    @options_illegal_chars = /[\$;&\|]/
                end
                if @config.pluginconf["puppetd.options_regex"]
                    @options_regex = Regexp.new(@config.pluginconf["puppetd.options_regex"])
                else
                    @options_regex = /(\-\-[\w\-]+)( +(=?["'\d\w][\w\-\d\."']+))?/
                end
            end

            action "enable" do
                enable
            end

            action "disable" do
                disable
            end

            action "runonce" do
                runonce
            end

            action "status" do
                status
            end

            private
            def status
                reply[:enabled] = 0
                reply[:running] = 0
                reply[:lastrun] = 0

                if File.exists?(@lockfile)
                    if File::Stat.new(@lockfile).zero?
                        reply[:output] = "Disabled, not running"
                    else
                        reply[:output] = "Enabled, running"
                        reply[:enabled] = 1
                        reply[:running] = 1
                    end
                else
                        reply[:output] = "Enabled, not running"
                        reply[:enabled] = 1
                end

                reply[:lastrun] = File.stat(@statefile).mtime.to_i if File.exists?(@statefile)
                reply[:output] += ", last run #{Time.now.to_i - reply[:lastrun]} seconds ago"
            end

            def runonce
                @puppetd_options = request[:puppetd_options]
                @options_parsed = @puppetd_options.scan(@options_regex)
                @options_illegal = @options_parsed.select{ |x| x if !@options_whitelist.include?(x[0]) }.map{|x| x[0]}
                                
                if @puppetd_options.scan(@options_illegal_chars).size > 0
                    reply.fail "Illegal charaters in puppeted options."
                    return
                end
                
                if @options_illegal.size > 0 
                    reply.fail "Illegal puppeted options: #{@options_illegal.join(',')}"
                    return
                end
                
                if File.exists?(@lockfile)
                    reply.fail "Lock file exists, puppetd is already running or it's disabled"
                else
                    if request[:forcerun]
                        reply[:output] = %x[#{@puppetd} --onetime #{@puppetd_options}]

                    elsif @splaytime > 0
                        reply[:output] = %x[#{@puppetd} --onetime --splaylimit #{@splaytime} --splay #{@puppetd_options}]

                    else
                        reply[:output] = %x[#{@puppetd} --onetime #{@puppetd_options}]
                    end
                end
            end

            def enable
                if File.exists?(@lockfile)
                    stat = File::Stat.new(@lockfile)

                    if stat.zero?
                        File.unlink(@lockfile)
                        reply[:output] = "Lock removed"
                    else
                        reply[:output] = "Currently runing"
                    end
                else
                    reply.fail "Already unlocked"
                end
            end

            def disable
                if File.exists?(@lockfile)
                    stat = File::Stat.new(@lockfile)

                    stat.zero? ? reply.fail("Already disabled") : reply.fail("Currently running")
                else
                    begin
                        File.open(@lockfile, "w") do |file|
                        end

                        reply[:output] = "Lock created"
                    rescue Exception => e
                        reply[:output] = "Could not create lock: #{e}"
                    end
                end
            end
        end
    end
end

# vi:tabstop=4:expandtab:ai:filetype=ruby
