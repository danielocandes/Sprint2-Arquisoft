import boto3
from moto import mock_aws

# cosas pa tener en cuenta:
# ejecutar antes: pip install boto3 moto

#Un resumen a grandes rasgos
#Para el ASR 1 (Velocidad de procesamiento): Usar el Script 1 (Moto) en el PC para simular la API de AWS y medir qué tan rápido tu código procesa los volúmenes huérfanos.

#Para el ASR 2 (Prueba de carga de reportes): * Paso A: Usar el Script 2 desde EC2 para llenar la BD real con cientos de miles de registros (esto es usar AWS directamente).

#Paso B: Usas una herramienta como JMeter desde el PC para "atacar" la IP pública del Balanceador de Cargas (alb_reportes) simulando a los 12.000 usuarios concurrentes pidiendo reportes.


# Tarifas públicas aproximadas de AWS (USD por GB mensual)
PRECIOS_VOLUMEN = {
    'gp2': 0.10,
    'gp3': 0.08,
    'io1': 0.125
}

@mock_aws
def test_manejador_cloud_huerfanos():
    """
    Simula la infraestructura de AWS y prueba la extracción de volúmenes huérfanos.
    Este decorador @mock_aws asegura que Boto3 NO se conecte a la cuenta real.
    """
    # 1. Configuración del cliente AWS simulado
    ec2 = boto3.client('ec2', region_name='us-east-1')
    
    print("--- GENERANDO INFRAESTRUCTURA FAKE EN MOTO ---")
    
    # 2. Generar "Ruido": Instancias EC2 con volúmenes adjuntos (Sanos / in-use)
    # Al correr una instancia, Moto le asigna automáticamente un volumen root.
    ec2.run_instances(ImageId='ami-12c6146b', MinCount=10, MaxCount=10, InstanceType='t2.micro')
    
    # 3. Generar Volúmenes Huérfanos (Estado: 'available')
    tamanos_gb = [8, 50, 100, 500, 1000]
    tipos = ['gp2', 'gp3', 'io1']
    
    for i in range(100): # Generamos 100 volúmenes huérfanos
        ec2.create_volume(
            AvailabilityZone='us-east-1a',
            Size=tamanos_gb[i % len(tamanos_gb)],
            VolumeType=tipos[i % len(tipos)]
        )
    print("Infraestructura simulada creada con éxito.\n")

    # =================================================================
    # A PARTIR DE AQUÍ ES LA LÓGICA QUE IRÍA EN EL CÓDIGO (manejador_cloud)
    # =================================================================
    print("--- LÓGICA DE EXTRACCIÓN (ASR 1) ---")
    
    # Consultar a AWS filtrando EXCLUSIVAMENTE por volúmenes no adjuntos
    respuesta = ec2.describe_volumes(Filters=[{'Name': 'status', 'Values': ['available']}])
    volumenes_huerfanos = respuesta.get('Volumes', [])
    
    # Calcular costo para cada volumen y preparar lista
    volumenes_procesados = []
    for vol in volumenes_huerfanos:
        tipo = vol['VolumeType']
        tamano = vol['Size']
        # Calcular el costo mensual estimado
        costo_estimado = tamano * PRECIOS_VOLUMEN.get(tipo, 0.10) 
        
        volumenes_procesados.append({
            'vol_id': vol['VolumeId'],
            'tipo': tipo,
            'tamano_gb': tamano,
            'costo_mensual': costo_estimado
        })
    
    # Ordenar por costo (de mayor a menor) para cumplir el requerimiento de negocio
    volumenes_ordenados = sorted(volumenes_procesados, key=lambda x: x['costo_mensual'], reverse=True)
    
    print(f"Total de volúmenes huérfanos detectados: {len(volumenes_ordenados)}")

if __name__ == '__main__':
    test_manejador_cloud_huerfanos()