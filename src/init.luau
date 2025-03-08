--!optimize 2
export type Connection<T...> = {
	Connected: boolean,
	Disconnect: (self: Connection<T...>) -> (),

	fn: (T...) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, (T...) -> ()) -> Connection<T...>,
	Once: (self: Signal<T...>, (T...) -> ()) -> Connection<T...>,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),

	--alias for cleanup modules
	Destroy: (self: Signal<T...>) -> (),
}

local spawn = task.spawn -- or task.defer

local spawn, running, yield = task.spawn, coroutine.running, coroutine.yield

local thread = nil

local signal = {}
signal.__index = signal

local connection = {}
connection.__index = connection

local function call(fn, ...)
	local running = thread
	thread = nil
	fn(...)
	thread = running
end

local function spawner()
	while true do
		call(yield())
	end
end

function connection:Disconnect()
	self.Connected = false

	if self.prev then
		self.prev.next = self.next
	end
	if self.next then
		self.next.prev = self.prev
	end
end

function signal.new<T...>(): Signal<T...>
	--why does setting them to false at the start slightly faster than not assigning it at start
	return setmetatable({ next = false, waiting = false }, signal)
end

function signal:Connect<T...>(fn: (T...) -> ()): Connection<T...>
	local next = self.next
	local connection = setmetatable({ fn = fn, next = next, prev = self, Connected = true }, connection)

	if next then
		next.prev = connection
	end
	self.next = connection
	return connection
end

function signal:Fire<T...>(...: T...)
	local n = self.next :: Connection<T...>
	while n do
		local fn = n.fn
		n = n.next

		if not thread then
			thread = coroutine.create(spawner)
			coroutine.resume(thread)
		end

		spawn(thread, fn, ...)
	end

	if self.waiting then
		local waiting = self.waiting
		self.waiting = false

		for i = 1, #waiting do
			coroutine.resume(waiting[i], ...)
		end
	end
end

function signal:Once<T...>(fn: (T...) -> ())
	local conn
	conn = self:Connect(function(...)
		fn(...)
		if conn.Connected then
			conn:Disconnect()
		end
	end)

	return conn
end

function signal:DisconnectAll()
	self.next = false
end
signal.Destroy = signal.DisconnectAll

function signal:Wait<T...>(): T...
	self.waiting = self.waiting or {}
	self.waiting[#self.waiting + 1] = running()
	return yield()
end

table.freeze(signal)
table.freeze(connection)
return signal
