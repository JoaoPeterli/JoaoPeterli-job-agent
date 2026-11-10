# Perfil do candidato usado pela ferramenta candidate_profile e pela nota
# de aderência. App pessoal: uma linha só (CandidateProfile.current).
class CreateCandidateProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :candidate_profiles do |t|
      t.string :skills, array: true, null: false, default: []
      t.string :seniority, null: false, default: "senior"
      t.boolean :remote, null: false, default: true
      t.string :location
      t.timestamps
    end
  end
end
