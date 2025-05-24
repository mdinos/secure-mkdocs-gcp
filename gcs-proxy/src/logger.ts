import pino from 'pino'

const PinoLevelToSeverityLookup: Record<string, string> = {
  trace: 'DEBUG',
  debug: 'DEBUG',
  info: 'INFO',
  warn: 'WARNING',
  error: 'ERROR',
  fatal: 'CRITICAL',
}

const defaultPinoConf = {
  messageKey: 'message',
  formatters: {
    level(label: string, number: number) {
      return {
        severity: PinoLevelToSeverityLookup[label] || PinoLevelToSeverityLookup['info'],
        level: number,
      }
    },
  },
}

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  ...defaultPinoConf,
})
