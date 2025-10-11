local Timer = {}
Timer.__index = Timer

-- Module Functions
function Timer.new(Duration, StartFinished)
	Duration = Duration or 0
	Duration = math.max(Duration, 0)
	local Data = {
		EndTime = StartFinished and 0 or (os.clock() + Duration);
		Duration = Duration;
	}
	setmetatable(Data, Timer)
	return Data
end

function Timer:Reset(NewDuration)
	if NewDuration then
		self.Duration = NewDuration
	end
	self.EndTime = os.clock() + self.Duration
end

function Timer:Finish()
	self.EndTime = os.clock() - 0.01
end

function Timer:GetTimeLeft()
	return math.max(0, self.EndTime - os.clock())
end

-- Returns:: 0 = start, 1 = done
function Timer:GetTimeLeftAsAlpha()
	return math.clamp(1 - ((self.EndTime - os.clock()) / self.Duration), 0, 1)
end

function Timer:IsDone()
	return os.clock() >= self.EndTime
end

function Timer:IsNotDone()
	return os.clock() < self.EndTime
end

return Timer
