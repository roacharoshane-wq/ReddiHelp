import { create } from 'zustand'

export const useSocketStore = create((set) => ({
  socket: null,
  connected: false,
  setSocket: (socket) => set({ socket }),
  setConnected: (connected) => set({ connected }),
  disconnect: () => {
    set((state) => {
      if (state.socket) state.socket.disconnect()
      return { socket: null, connected: false }
    })
  },
}))
