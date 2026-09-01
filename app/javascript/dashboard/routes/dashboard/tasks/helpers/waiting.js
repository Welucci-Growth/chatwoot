// A client who spoke last is waiting on us. Past two hours the wait is shown in red, on the
// board and inside the card alike.
export const RED_AFTER_MINUTES = 120;

const shortDuration = minutes => {
  if (minutes < 60) return `${minutes}min`;
  const hours = Math.floor(minutes / 60);
  return hours < 24 ? `${hours}h` : `${Math.floor(hours / 24)}d`;
};

export const waitingInfo = (waitingSince, now = Date.now()) => {
  if (!waitingSince) return null;

  const minutes = Math.max(0, Math.floor((now - waitingSince * 1000) / 60000));
  return {
    minutes,
    label: shortDuration(minutes),
    isLate: minutes >= RED_AFTER_MINUTES,
  };
};
