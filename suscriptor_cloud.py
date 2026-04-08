import pika
import boto3
import psycopg2
import time

# CONFIGURACIÓN RECUPERADA
RABBIT_IP = "172.31.28.147"
DB_HOST = "reportes-bd-negocio.clxtg6hte7ux.us-east-1.rds.amazonaws.com"
DB_NAME = "bdnegocio"
DB_USER = "postgresadmin"
DB_PASS = "Arquisoft2026!"

def guardar_en_db(volumen_id, tamaño, costo):
    try:
        conn = psycopg2.connect(
            host=DB_HOST, 
            database=DB_NAME, 
            user=DB_USER, 
            password=DB_PASS
        )
        cur = conn.cursor()

        cur.execute("CREATE TABLE IF NOT EXISTS reportes_ebs (id TEXT PRIMARY KEY, size INT, cost FLOAT);")

        cur.execute("""
            INSERT INTO reportes_ebs (id, size, cost) 
            VALUES (%s, %s, %s) 
            ON CONFLICT (id) DO UPDATE SET cost = EXCLUDED.cost;
        """, (volumen_id, tamaño, costo))
        
        conn.commit()
        print(f" [v] Guardado en RDS: {volumen_id}")
        
        cur.close()
        conn.close()
    except Exception as e:
        print(f" [!] Error en DB: {e}")

def callback(ch, method, properties, body):
    if body.decode() == "EJECUTAR_REPORTE_EBS":
        print("\n [!] Mensaje recibido: Escaneando AWS...")
        
        guardar_en_db("control-check", 0, 0.0)

        try:
            ec2 = boto3.client('ec2', region_name='us-east-1')
            vols = ec2.describe_volumes(Filters=[{'Name': 'status', 'Values': ['available']}])

            for v in vols['Volumes']:
                vid = v['VolumeId']
                size = v['Size']
                costo = size * 0.1 
                guardar_en_db(vid, size, costo)
            
            print(" [v] Escaneo completado y RDS actualizada.")
        except Exception as e:
            print(f" [!] Error AWS: {e}")

# CONEXIÓN A RABBITMQ
try:
    creds = pika.PlainCredentials('admin', 'Arquisoft2026!')
    conn_params = pika.ConnectionParameters(host=RABBIT_IP, credentials=creds)
    connection = pika.BlockingConnection(conn_params)
    channel = connection.channel()
    channel.queue_declare(queue='cola_reportes')

    channel.basic_consume(queue='cola_reportes', on_message_callback=callback, auto_ack=True)

    print(' [*] Worker ONLINE y conectado a RDS. Esperando mensajes...')
    channel.start_consuming()
except Exception as e:
    print(f" [!] Error de conexión: {e}")
