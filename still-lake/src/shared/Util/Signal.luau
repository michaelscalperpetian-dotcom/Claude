--!strict
-- Minimal signal for module-to-module events (no Instances, no yielding).

export type Connection = { disconnect: () -> () }

export type Signal<T...> = {
	connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { (T...) -> () } = {}

	local self = {}

	function self.connect(_: any, fn: (T...) -> ()): Connection
		table.insert(handlers, fn)
		return {
			disconnect = function()
				local index = table.find(handlers, fn)
				if index then
					table.remove(handlers, index)
				end
			end,
		}
	end

	function self.fire(_: any, ...: T...)
		for _, fn in table.clone(handlers) do
			task.spawn(fn, ...)
		end
	end

	return (self :: any) :: Signal<T...>
end

return Signal
