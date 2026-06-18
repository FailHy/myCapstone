from pathlib import Path
import pandas as pd

input_path = 'dataset/data_training.csv'
df = pd.read_csv(input_path)

mapping = {
    'session_01': ('correct', 'correct', 'good_form'),
    'session_02': ('incorrect', 'body_swing', 'badan_bergerak'),
    'session_03': ('incorrect', 'elbow_swing', 'siku_maju_mundur'),
    'session_04': ('incorrect', 'not_full_up', 'rom_tidak_penuh'),
    'session_05': ('incorrect', 'too_fast', 'tempo_terlalu_cepat')
}

mask = df['subject_id'].astype(str).eq('S06')

for session, values in mapping.items():
    session_mask = mask & df['session_id'].astype(str).str.contains(session, na=False)
    df.loc[session_mask, ['label', 'error_type', 'notes']] = values

output_path = 'dataset/data_training_S06_remapped.csv'
df.to_csv(output_path, index=False)

print("Total data S06:", mask.sum())
print(df.loc[mask, ['subject_id','exercise_type','session_id','label','error_type','notes']].head(20))
print(f"Saved to {output_path}")
