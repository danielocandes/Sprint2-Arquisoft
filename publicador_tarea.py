import pika

def disparar_analisis():

    RABBIT_IP = '172.31.28.147'

    creds = pika.PlainCredentials('admin', 'Arquisoft2026!')
    
    try:
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host=RABBIT_IP, credentials=creds)
        )
        channel = connection.channel()

        channel.queue_declare(queue='cola_reportes')

        channel.basic_publish(
            exchange='',
            routing_key='cola_reportes',
            body='EJECUTAR_REPORTE_EBS'
        )
        
        print(" [x] Enviado: EJECUTAR_REPORTE_EBS")
        connection.close()
    except Exception as e:
        print(f" [!] Error al publicar: {e}")

if __name__ == "__main__":
    disparar_analisis()
