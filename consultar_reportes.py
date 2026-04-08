import psycopg2
import time


DB_HOST = "reportes-bd-negocio.clxtg6hte7ux.us-east-1.rds.amazonaws.com" 
DB_NAME = "bdnegocio"
DB_USER = "postgresadmin"
DB_PASS = "Arquisoft2026!"

def simular_consulta_usuario():
    try:
        start_time = time.time()
        
        conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS)
        cur = conn.cursor()
        

        cur.execute("SELECT id, size, cost FROM reportes_ebs ORDER BY cost DESC;")
        rows = cur.fetchall()
        
        end_time = time.time()
        duration_ms = (end_time - start_time) * 1000 

        print(f"\n--- RESPUESTA DEL SERVIDOR ---")
        print(f"Tiempo de respuesta: {duration_ms:.2f} ms")
        print(f"Cumple ASR (< 300ms): {'SÍ' if duration_ms < 300 else 'NO'}")
        print("-" * 30)
        for row in rows:
            print(f"Volumen: {row[0]} | Costo: ${row[2]}")
            
        cur.close()
        conn.close()
    except Exception as e:
        print(f"Error en la consulta: {e}")

if __name__ == "__main__":
    simular_consulta_usuario()
