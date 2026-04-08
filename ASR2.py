import psycopg2
from psycopg2.extras import execute_values
from faker import Faker
import random

# cosas pa tener en cuenta:
# ejecutar antes: pip install psycopg2-binary faker
#ajustar credenciales de la base de datos

# Instanciar Faker
fake = Faker()

# =================================================================
# CONFIGURACIÓN DE BASE DE DATOS (Ajusta valores de acuerdo a Terraform)
# =================================================================
DB_HOST = "pon-aqui-el-endpoint-de-tu-rds.us-east-1.rds.amazonaws.com"
DB_NAME = "bdnegocio"
DB_USER = "tu_usuario"
DB_PASSWORD = "tu_password"

def poblar_base_de_datos_reportes():
    # 1. Conexión a PostgreSQL
    try:
        conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)
        cursor = conn.cursor()
    except Exception as e:
        print(f"Error conectando a la BD: {e}")
        return

    # 2. Creación de tabla e índices para el ASR 2 (< 100ms)
    print("Configurando esquema y optimizando índices...")
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS reporte_costos_mensuales (
            id SERIAL PRIMARY KEY,
            empresa_id INT,
            proyecto_id INT,
            servicio_aws VARCHAR(50),
            mes_anio VARCHAR(7), -- Formato 'YYYY-MM'
            costo_usd NUMERIC(10, 2)
        );
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_reporte_empresa_mes ON reporte_costos_mensuales(empresa_id, mes_anio);")
    conn.commit()

    # 3. Generación de Mock Data Masiva
    print("Generando datos sintéticos en memoria (Esto puede tomar unos segundos)...")
    datos_a_insertar = []
    servicios_cloud = ['EC2', 'RDS', 'S3', 'EKS', 'Lambda', 'CloudFront', 'DynamoDB']
    
    # Como ejemplo, se simulan 200 Empresas x 5 Proyectos x 12 Meses x 7 Servicios = 84,000 registros
    for empresa_id in range(1, 201):
        for proyecto_id in range(1, 6):
            for mes in range(1, 13):
                mes_anio = f"2026-{mes:02d}"
                for servicio in servicios_cloud:
                    # Generar un costo aleatorio realista
                    costo = round(random.uniform(5.0, 2500.0), 2)
                    datos_a_insertar.append((empresa_id, proyecto_id, servicio, mes_anio, costo))

    print(f"Insertando {len(datos_a_insertar)} registros en RDS...")
    query_insercion = """
        INSERT INTO reporte_costos_mensuales 
        (empresa_id, proyecto_id, servicio_aws, mes_anio, costo_usd) 
        VALUES %s
    """
    execute_values(cursor, query_insercion, datos_a_insertar)
    
    conn.commit()
    cursor.close()
    conn.close()
    print("¡Poblado de base de datos finalizado exitosamente!")

if __name__ == '__main__':
    # PRECAUCIÓN: Asegúrarse de tener los Security Groups de la BD abiertos a la IP 
    # o correr este script desde una instancia (ej. el manejador_cloud) dentro de la VPC.
    poblar_base_de_datos_reportes()