
require "terminal-notifier"

class Notifier

	@@default_options = {:title => "Fire.app"}

	def self.notify(msg, options = {})
		options = @@default_options.merge(options)
		TerminalNotifier.notify(msg, options) #if org.jruby.platform.Platform::IS_MAC 
	end

	def self.is_support
		org.jruby.platform.Platform::IS_MAC && java.lang.System.getProperty("os.version").to_f >= 10.8
	end

end