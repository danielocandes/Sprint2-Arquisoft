import pika, boto3, psycopg2

# CONFIGURACIÓN
RABBIT_IP = "172.31.28.147"
DB_HOST = "reportes-bd-negocio.clxtg6hte7ux.us-east-1.rds.amazonaws.com"

def guardar_en_db(volumen_id, tamaño, costo):
    try:
        conn = psycopg2.connect(host=DB_HOST, database="bdnegocio", user="postgresadmin", password="Arquisoft2026!")
        cur = conn.cursor()
        cur.execute("CREATE TABLE IF NOT EXISTS reportes_ebs (id TEXT PRIMARY KEY, size INT, cost FLOAT);")
        cur.execute("INSERT INTO reportes_ebs (id, size, cost) VALUES (%s, %s, %s) ON CONFLICT (id) DO UPDATE SET cost = EXCLUDED.cost;", (volumen_id, tamaño, costo))
        conn.commit()
        print(f" [v] Guardado: {volumen_id}")
        cur.close()
        conn.close()
    except Exception as e:
        print(f" [!] Error RDS: {e}")

def callback(ch, method, properties, body):
    if body.decode() == "EJECUTAR_REPORTE_EBS":
        print(" [!] Procesando...")
        guardar_en_db("control-check", 0, 0.0)
        try:
            ec2 = boto3.client('ec2', region_name='us-east-1')
            vols = ec2.describe_volumes(Filters=[{'Name': 'status', 'Values': ['available']}])
            for v in vols['Volumes']:
                guard_en_db(v['VolumeId'], v['Size'], v['Size'] * 0.1)
            print(" [v] Terminado.")
        except Exception as e:
            print(f" [!] Error AWS: {e}")

# CONEXIÓN A RABBITMQ
creds = pika.PlainCredentials('admin', 'Arquisoft2026!')
conn_params = pika.ConnectionParameters(
    host='172.31.28.147', 
    port=5672, 
    virtual_host='/', 
    credentials=creds
)
connection = pika.BlockingConnection(conn_params)
channel = connection.channel()
channel.queue_declare(queue='cola_reportes')
channel.basic_consume(queue='cola_reportes', on_message_callback=callback, auto_ack=True)

print(' [*] Worker ONLINE. Esperando mensajes...')
channel.start_consuming()
