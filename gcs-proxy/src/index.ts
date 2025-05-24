import express, { Request, Response } from 'express'
import { Storage } from '@google-cloud/storage'

import { logger } from './logger'

const app = express()
const storage = new Storage()

const bucketName = process.env.BUCKET_NAME

if (!bucketName) {
  logger.error('BUCKET_NAME environment variable is not set.')
  throw new Error('Environment variable BUCKET_NAME is required.')
}

const bucket = storage.bucket(bucketName)

app.get('/healthcheck', (_req, res) => {
  res.status(200).json({
    status: 'ok',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  })
})

app.get('/{*splat}', async (req: Request, res: Response) => {
  const filePath = req.params.splat === '' ? 'index.html' : req.params.splat;
  logger.debug('Request Path', { path: filePath })
  logger.debug('Request Headers', { headers: req.headers })

  const file = bucket.file(filePath)

  try {
    const [exists] = await file.exists()
    if (!exists) {
      res.status(404).send('Not found')
      return
    }

    res.set('Cache-Control', 'no-cache')
    file
      .createReadStream()
      .on('error', () => res.status(500).send('Server error'))
      .pipe(res)
  } catch (err) {
    logger.error('Error serving file:', { err })
    res.status(500).send('Internal server error')
  }
})

const port = process.env.PORT || 8080
app.listen(port, () => {
  logger.info(`Server listening on port ${port}`)
})
