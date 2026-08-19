/// Strength programs bundled with the app, organised by experience level.
/// Content follows established, well-documented programs — sources are
/// named per program and shown in the UI. Weights in kg; linear
/// progression (+increment per successful exercise, deload −10% after
/// three misses). Serializable so user-created programs share the model.
library;

class ProgramExercise {
  final String name;
  final int sets;
  final int reps;
  final double startKg;
  final double incrementKg;

  /// One-line form cue shown during the workout. Step-by-step guidance
  /// lives in ExerciseGuides (keyed by name).
  final String cue;

  const ProgramExercise({
    required this.name,
    required this.sets,
    required this.reps,
    required this.startKg,
    required this.incrementKg,
    this.cue = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'sets': sets,
        'reps': reps,
        'startKg': startKg,
        'incrementKg': incrementKg,
        'cue': cue,
      };

  factory ProgramExercise.fromJson(Map<String, dynamic> m) => ProgramExercise(
        name: m['name'] as String? ?? 'Exercise',
        sets: (m['sets'] as num?)?.toInt() ?? 3,
        reps: (m['reps'] as num?)?.toInt() ?? 8,
        startKg: (m['startKg'] as num?)?.toDouble() ?? 20,
        incrementKg: (m['incrementKg'] as num?)?.toDouble() ?? 2.5,
        cue: m['cue'] as String? ?? '',
      );
}

class ProgramDay {
  final String title;
  final List<ProgramExercise> exercises;
  const ProgramDay({required this.title, required this.exercises});

  Map<String, dynamic> toJson() => {
        'title': title,
        'exercises': [for (final e in exercises) e.toJson()],
      };

  factory ProgramDay.fromJson(Map<String, dynamic> m) => ProgramDay(
        title: m['title'] as String? ?? 'Day',
        exercises: [
          for (final e in (m['exercises'] as List? ?? const []))
            if (e is Map) ProgramExercise.fromJson(e.cast<String, dynamic>()),
        ],
      );
}

class Program {
  final String id;
  final String name;
  final String daysPerWeek;

  /// Beginner | Intermediate | Advanced | Custom
  final String experience;
  final String description;
  final String source;
  final List<ProgramDay> days;

  const Program({
    required this.id,
    required this.name,
    required this.daysPerWeek,
    required this.experience,
    required this.description,
    required this.source,
    required this.days,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'daysPerWeek': daysPerWeek,
        'experience': experience,
        'description': description,
        'source': source,
        'days': [for (final d in days) d.toJson()],
      };

  factory Program.fromJson(Map<String, dynamic> m) => Program(
        id: m['id'] as String? ?? 'custom',
        name: m['name'] as String? ?? 'Custom program',
        daysPerWeek: m['daysPerWeek'] as String? ?? '',
        experience: m['experience'] as String? ?? 'Custom',
        description: m['description'] as String? ?? '',
        source: m['source'] as String? ?? 'Your own program',
        days: [
          for (final d in (m['days'] as List? ?? const []))
            if (d is Map) ProgramDay.fromJson(d.cast<String, dynamic>()),
        ],
      );
}

class TrainingPrograms {
  TrainingPrograms._();

  static Program? byId(String? id) {
    if (id == null) return null;
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static const all = <Program>[
    // ── BEGINNER · Full-body Basics (StrongLifts 5×5) ────────────────────
    Program(
      id: 'sl5x5',
      name: 'Full-body Basics',
      daysPerWeek: '3 days/week',
      experience: 'Beginner',
      description:
          'Two alternating full-body workouts built on the big barbell '
          'lifts, five sets of five. The simplest proven way to get '
          'strong: add 2.5 kg every successful workout. Based on '
          'StrongLifts 5×5.',
      source: 'StrongLifts 5×5 — Mehdi Hadim, stronglifts.com',
      days: [
        ProgramDay(title: 'Full body 1', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 5, reps: 5, startKg: 20, incrementKg: 2.5,
              cue: 'Hip crease below the knee, drive up through mid-foot.'),
          ProgramExercise(
              name: 'Bench press', sets: 5, reps: 5, startKg: 20,
              incrementKg: 2.5,
              cue: 'Shoulder blades pinched, bar to mid-chest.'),
          ProgramExercise(
              name: 'Barbell row', sets: 5, reps: 5, startKg: 30,
              incrementKg: 2.5,
              cue: 'Hinge to ~45°, pull to lower chest, no jerking.'),
          ProgramExercise(
              name: 'Triceps pushdown', sets: 3, reps: 10, startKg: 20,
              incrementKg: 2.5,
              cue: 'Accessory: elbows pinned, full lockout.'),
        ]),
        ProgramDay(title: 'Full body 2', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 5, reps: 5, startKg: 20, incrementKg: 2.5,
              cue: 'Hip crease below the knee, drive up through mid-foot.'),
          ProgramExercise(
              name: 'Overhead press', sets: 5, reps: 5, startKg: 20,
              incrementKg: 2.5,
              cue: 'Squeeze glutes, press up and slightly back.'),
          ProgramExercise(
              name: 'Deadlift', sets: 1, reps: 5, startKg: 40, incrementKg: 5,
              cue: 'One heavy set. Flat back, push the floor away.'),
          ProgramExercise(
              name: 'Biceps curl', sets: 3, reps: 10, startKg: 10,
              incrementKg: 2,
              cue: 'Accessory: elbows still, no swinging.'),
        ]),
      ],
    ),

    // ── BEGINNER · Full-body Variety (GZCLP) ─────────────────────────────
    Program(
      id: 'gzclp',
      name: 'Full-body Variety',
      daysPerWeek: '3 days/week',
      experience: 'Beginner',
      description:
          'Full-body with more variety: a heavy main lift (5×3), a '
          'lighter secondary lift (3×10) and accessory work (3×15) each '
          'day. Based on GZCLP.',
      source: 'GZCLP — Cody Lefever (GZCL), r/Fitness program wiki',
      days: [
        ProgramDay(title: 'Variety Day 1', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 5, reps: 3, startKg: 30, incrementKg: 2.5,
              cue: 'Heavy crisp triples — stop when bar speed grinds.'),
          ProgramExercise(
              name: 'Bench press', sets: 3, reps: 10, startKg: 20,
              incrementKg: 2.5,
              cue: 'Lighter weight, full range, controlled tempo.'),
          ProgramExercise(
              name: 'Lat pulldown', sets: 3, reps: 15, startKg: 25,
              incrementKg: 2.5,
              cue: 'Pull to upper chest, elbows down and back.'),
          ProgramExercise(
              name: 'Biceps curl', sets: 3, reps: 15, startKg: 8,
              incrementKg: 2,
              cue: 'Light and strict — squeeze at the top.'),
        ]),
        ProgramDay(title: 'Variety Day 2', exercises: [
          ProgramExercise(
              name: 'Overhead press', sets: 5, reps: 3, startKg: 20,
              incrementKg: 2.5,
              cue: 'Tight core, straight bar path, head through.'),
          ProgramExercise(
              name: 'Deadlift', sets: 3, reps: 10, startKg: 40,
              incrementKg: 5,
              cue: 'Reset each rep, hips and shoulders rise together.'),
          ProgramExercise(
              name: 'Dumbbell row', sets: 3, reps: 15, startKg: 12,
              incrementKg: 2,
              cue: 'Knee on bench, pull to hip, squeeze.'),
          ProgramExercise(
              name: 'Lateral raise', sets: 3, reps: 15, startKg: 6,
              incrementKg: 2,
              cue: 'Slight elbow bend, raise to shoulder height.'),
        ]),
        ProgramDay(title: 'Variety Day 3', exercises: [
          ProgramExercise(
              name: 'Bench press', sets: 5, reps: 3, startKg: 25,
              incrementKg: 2.5,
              cue: 'Heavy triples — keep leg drive and tightness.'),
          ProgramExercise(
              name: 'Squat', sets: 3, reps: 10, startKg: 25,
              incrementKg: 2.5,
              cue: 'Lighter tens — sit back, stay upright.'),
          ProgramExercise(
              name: 'Face pull', sets: 3, reps: 15, startKg: 15,
              incrementKg: 2,
              cue: 'Rope to eyebrows, elbows high, pause.'),
          ProgramExercise(
              name: 'Triceps pushdown', sets: 3, reps: 15, startKg: 15,
              incrementKg: 2.5,
              cue: 'Elbows pinned, full lockout, slow return.'),
        ]),
      ],
    ),

    // ── INTERMEDIATE · Upper / Lower (4 days) ────────────────────────────
    Program(
      id: 'upperlower',
      name: 'Upper / Lower Split',
      daysPerWeek: '4 days/week',
      experience: 'Intermediate',
      description:
          'Four days alternating upper and lower body: heavy power days '
          'and higher-rep hypertrophy days. Inspired by PHUL (Power '
          'Hypertrophy Upper Lower).',
      source: 'PHUL — Brandon Campbell; r/Fitness program wiki',
      days: [
        ProgramDay(title: 'Upper Power', exercises: [
          ProgramExercise(
              name: 'Bench press', sets: 4, reps: 5, startKg: 40,
              incrementKg: 2.5,
              cue: 'Heavy fives — leg drive, tight upper back.'),
          ProgramExercise(
              name: 'Barbell row', sets: 4, reps: 5, startKg: 40,
              incrementKg: 2.5,
              cue: 'Strict hinge, pull to lower chest.'),
          ProgramExercise(
              name: 'Overhead press', sets: 3, reps: 8, startKg: 25,
              incrementKg: 2.5,
              cue: 'Straight line up, glutes tight.'),
          ProgramExercise(
              name: 'Lat pulldown', sets: 3, reps: 10, startKg: 35,
              incrementKg: 2.5,
              cue: 'Chest up, elbows down, pause at the chest.'),
          ProgramExercise(
              name: 'Biceps curl', sets: 3, reps: 10, startKg: 12,
              incrementKg: 2,
              cue: 'Elbows still, control the negative.'),
        ]),
        ProgramDay(title: 'Lower Power', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 4, reps: 5, startKg: 50, incrementKg: 2.5,
              cue: 'Heavy fives — brace hard, full depth.'),
          ProgramExercise(
              name: 'Deadlift', sets: 3, reps: 5, startKg: 60, incrementKg: 5,
              cue: 'Flat back, bar close, stand tall.'),
          ProgramExercise(
              name: 'Leg press', sets: 3, reps: 10, startKg: 100,
              incrementKg: 5,
              cue: 'Depth without the lower back leaving the pad.'),
          ProgramExercise(
              name: 'Standing calf raise', sets: 4, reps: 10, startKg: 50,
              incrementKg: 5,
              cue: 'Pause top and bottom — no bouncing.'),
        ]),
        ProgramDay(title: 'Upper Hypertrophy', exercises: [
          ProgramExercise(
              name: 'Incline dumbbell press', sets: 4, reps: 10, startKg: 16,
              incrementKg: 2,
              cue: '30–45° bench, full stretch at the bottom.'),
          ProgramExercise(
              name: 'Dumbbell row', sets: 4, reps: 10, startKg: 20,
              incrementKg: 2,
              cue: 'Pull to hip, squeeze the lat.'),
          ProgramExercise(
              name: 'Lateral raise', sets: 3, reps: 12, startKg: 8,
              incrementKg: 2,
              cue: 'To shoulder height, no swing.'),
          ProgramExercise(
              name: 'Face pull', sets: 3, reps: 15, startKg: 15,
              incrementKg: 2,
              cue: 'Rope to eyebrows, elbows high.'),
          ProgramExercise(
              name: 'Triceps pushdown', sets: 3, reps: 12, startKg: 20,
              incrementKg: 2.5,
              cue: 'Full lockout, slow return.'),
        ]),
        ProgramDay(title: 'Lower Hypertrophy', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 4, reps: 10, startKg: 40, incrementKg: 2.5,
              cue: 'Lighter tens — steady tempo, full depth.'),
          ProgramExercise(
              name: 'Romanian deadlift', sets: 3, reps: 10, startKg: 40,
              incrementKg: 2.5,
              cue: 'Hips back, hamstring stretch, flat back.'),
          ProgramExercise(
              name: 'Walking lunge', sets: 3, reps: 10, startKg: 12,
              incrementKg: 2,
              cue: 'Long steps, knee tracks over toes.'),
          ProgramExercise(
              name: 'Seated calf raise', sets: 4, reps: 12, startKg: 30,
              incrementKg: 5,
              cue: 'Slow reps, full range.'),
        ]),
      ],
    ),

    // ── INTERMEDIATE · Push Pull Legs ────────────────────────────────────
    Program(
      id: 'ppl',
      name: 'Push Pull Legs',
      daysPerWeek: '5–6 days/week',
      experience: 'Intermediate',
      description:
          'Rotate Push, Pull and Legs days — run it 5 or 6 days a week, '
          'the app serves the next day in the rotation. The well-known '
          'Reddit PPL.',
      source: 'Reddit PPL — Metallicadpa, r/Fitness program wiki',
      days: [
        ProgramDay(title: 'Push', exercises: [
          ProgramExercise(
              name: 'Bench press', sets: 4, reps: 5, startKg: 30,
              incrementKg: 2.5,
              cue: 'Shoulder blades pinched, bar to mid-chest.'),
          ProgramExercise(
              name: 'Overhead press', sets: 3, reps: 8, startKg: 20,
              incrementKg: 2.5,
              cue: 'Squeeze glutes, straight bar path.'),
          ProgramExercise(
              name: 'Incline dumbbell press', sets: 3, reps: 10, startKg: 14,
              incrementKg: 2,
              cue: '30–45° bench, elbows ~45° from body.'),
          ProgramExercise(
              name: 'Lateral raise', sets: 3, reps: 12, startKg: 6,
              incrementKg: 2,
              cue: 'To shoulder height, controlled down.'),
          ProgramExercise(
              name: 'Triceps pushdown', sets: 3, reps: 12, startKg: 20,
              incrementKg: 2.5,
              cue: 'Elbows pinned, full lockout.'),
        ]),
        ProgramDay(title: 'Pull', exercises: [
          ProgramExercise(
              name: 'Deadlift', sets: 1, reps: 5, startKg: 60, incrementKg: 5,
              cue: 'One heavy set — brace hard, bar close.'),
          ProgramExercise(
              name: 'Barbell row', sets: 4, reps: 8, startKg: 30,
              incrementKg: 2.5,
              cue: 'Hinge to ~45°, pull to lower chest.'),
          ProgramExercise(
              name: 'Lat pulldown', sets: 3, reps: 10, startKg: 30,
              incrementKg: 2.5,
              cue: 'Chest up, elbows down, pause.'),
          ProgramExercise(
              name: 'Face pull', sets: 3, reps: 12, startKg: 15,
              incrementKg: 2,
              cue: 'Rope to eyebrows, elbows high.'),
          ProgramExercise(
              name: 'Biceps curl', sets: 3, reps: 12, startKg: 10,
              incrementKg: 2,
              cue: 'No swinging, squeeze at the top.'),
        ]),
        ProgramDay(title: 'Legs', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 4, reps: 5, startKg: 40, incrementKg: 2.5,
              cue: 'Below parallel, knees over toes, drive up.'),
          ProgramExercise(
              name: 'Romanian deadlift', sets: 3, reps: 10, startKg: 40,
              incrementKg: 2.5,
              cue: 'Hips back, hamstring stretch, flat back.'),
          ProgramExercise(
              name: 'Leg press', sets: 3, reps: 10, startKg: 80,
              incrementKg: 5,
              cue: 'Depth without the lower back rounding.'),
          ProgramExercise(
              name: 'Leg curl', sets: 3, reps: 10, startKg: 25,
              incrementKg: 2.5,
              cue: 'Squeeze the hamstring, slow return.'),
          ProgramExercise(
              name: 'Standing calf raise', sets: 4, reps: 12, startKg: 40,
              incrementKg: 5,
              cue: 'Pause top and bottom.'),
        ]),
      ],
    ),

    // ── INTERMEDIATE · 5/3/1 for Beginners ───────────────────────────────
    Program(
      id: '531beg',
      name: '5/3/1 for Beginners',
      daysPerWeek: '3 days/week',
      experience: 'Intermediate',
      description:
          'Based on Jim Wendler’s 5/3/1. Focuses on the four big lifts '
          'with a unique rep structure and progression. High frequency '
          'and effective. Includes 50–100 reps of accessory work.',
      source: '5/3/1 for Beginners — Jim Wendler, jimwendler.com',
      days: [
        ProgramDay(title: 'Day 1: Squat & Bench', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 3, reps: 5, startKg: 30, incrementKg: 2.5,
              cue: 'Main: 5/3/1 sets. Focus on form and depth.'),
          ProgramExercise(
              name: 'Bench press', sets: 3, reps: 5, startKg: 20,
              incrementKg: 2.5,
              cue: 'Main: 5/3/1 sets. Controlled descent.'),
          ProgramExercise(
              name: 'Pull-up', sets: 5, reps: 10, startKg: 0,
              incrementKg: 1,
              cue: 'Accessory: 50-100 total reps of pull.'),
          ProgramExercise(
              name: 'Push-up', sets: 5, reps: 10, startKg: 0,
              incrementKg: 1,
              cue: 'Accessory: 50-100 total reps of push.'),
          ProgramExercise(
              name: 'Ab wheel', sets: 5, reps: 10, startKg: 0,
              incrementKg: 1,
              cue: 'Accessory: 50-100 total reps of core.'),
        ]),
        ProgramDay(title: 'Day 2: Deadlift & OHP', exercises: [
          ProgramExercise(
              name: 'Deadlift', sets: 3, reps: 5, startKg: 40, incrementKg: 5,
              cue: 'Main: 5/3/1 sets. Neutral spine, drive with legs.'),
          ProgramExercise(
              name: 'Overhead press', sets: 3, reps: 5, startKg: 20,
              incrementKg: 2.5,
              cue: 'Main: 5/3/1 sets. Tight core, head through.'),
          ProgramExercise(
              name: 'Chin-up', sets: 5, reps: 10, startKg: 0,
              incrementKg: 1,
              cue: 'Accessory: 50-100 total reps of pull.'),
          ProgramExercise(
              name: 'Dips', sets: 5, reps: 10, startKg: 0,
              incrementKg: 1,
              cue: 'Accessory: 50-100 total reps of push.'),
          ProgramExercise(
              name: 'Plank', sets: 3, reps: 60, startKg: 0,
              incrementKg: 0,
              cue: 'Accessory: 50-100 total reps of core.'),
        ]),
      ],
    ),

    // ── INTERMEDIATE · PHUL Split ────────────────────────────────────────
    Program(
      id: 'phul_full',
      name: 'PHUL Split',
      daysPerWeek: '4 days/week',
      experience: 'Intermediate',
      description:
          'Power Hypertrophy Upper Lower. Combines strength and size '
          'training. Two power days and two hypertrophy days. '
          'A proven standard for intermediate lifters.',
      source: 'PHUL — Brandon Campbell, r/Fitness program wiki',
      days: [
        ProgramDay(title: 'Upper Power', exercises: [
          ProgramExercise(
              name: 'Bench press', sets: 4, reps: 5, startKg: 40,
              incrementKg: 2.5,
              cue: 'Power: 3-5 reps. Explosive on the way up.'),
          ProgramExercise(
              name: 'Incline dumbbell press', sets: 4, reps: 8, startKg: 16,
              incrementKg: 2,
              cue: 'Hypertrophy: 6-10 reps. Full stretch.'),
          ProgramExercise(
              name: 'Barbell row', sets: 4, reps: 5, startKg: 40,
              incrementKg: 2.5,
              cue: 'Power: 3-5 reps. Strict form.'),
          ProgramExercise(
              name: 'Lat pulldown', sets: 4, reps: 10, startKg: 35,
              incrementKg: 2.5,
              cue: 'Hypertrophy: 8-12 reps. Squeeze lats.'),
          ProgramExercise(
              name: 'Overhead press', sets: 3, reps: 8, startKg: 25,
              incrementKg: 2.5,
              cue: 'Strict press. Squeeze glutes.'),
        ]),
        ProgramDay(title: 'Lower Power', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 4, reps: 5, startKg: 50, incrementKg: 2.5,
              cue: 'Power: 3-5 reps. Control the descent.'),
          ProgramExercise(
              name: 'Deadlift', sets: 3, reps: 5, startKg: 60, incrementKg: 5,
              cue: 'Power: 3-5 reps. Explode from the floor.'),
          ProgramExercise(
              name: 'Leg press', sets: 3, reps: 12, startKg: 100,
              incrementKg: 5,
              cue: 'Hypertrophy: 10-15 reps. Full range.'),
          ProgramExercise(
              name: 'Leg curl', sets: 3, reps: 12, startKg: 25,
              incrementKg: 2.5,
              cue: 'Hypertrophy: 10-15 reps. Squeeze hamstrings.'),
        ]),
        ProgramDay(title: 'Upper Hypertrophy', exercises: [
          ProgramExercise(
              name: 'Bench press', sets: 4, reps: 10, startKg: 30,
              incrementKg: 2.5,
              cue: 'Hypertrophy: 8-12 reps. Focus on the pump.'),
          ProgramExercise(
              name: 'Incline dumbbell press', sets: 3, reps: 12, startKg: 14,
              incrementKg: 2,
              cue: 'Hypertrophy: 10-15 reps. Controlled tempo.'),
          ProgramExercise(
              name: 'Barbell row', sets: 4, reps: 10, startKg: 30,
              incrementKg: 2.5,
              cue: 'Hypertrophy: 8-12 reps. Squeeze shoulder blades.'),
          ProgramExercise(
              name: 'Cable row', sets: 3, reps: 12, startKg: 25,
              incrementKg: 2.5,
              cue: 'Hypertrophy: 10-15 reps. Pull to waist.'),
          ProgramExercise(
              name: 'Lateral raise', sets: 3, reps: 15, startKg: 6,
              incrementKg: 2,
              cue: 'Hypertrophy: 12-20 reps. Lead with elbows.'),
        ]),
        ProgramDay(title: 'Lower Hypertrophy', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 4, reps: 12, startKg: 35, incrementKg: 2.5,
              cue: 'Hypertrophy: 8-12 reps. Stay upright.'),
          ProgramExercise(
              name: 'Romanian deadlift', sets: 3, reps: 12, startKg: 40,
              incrementKg: 2.5,
              cue: 'Hypertrophy: 10-15 reps. Feel the stretch.'),
          ProgramExercise(
              name: 'Leg extension', sets: 3, reps: 15, startKg: 20,
              incrementKg: 2.5,
              cue: 'Hypertrophy: 12-20 reps. Hold the peak contraction.'),
          ProgramExercise(
              name: 'Leg curl', sets: 3, reps: 15, startKg: 20,
              incrementKg: 2.5,
              cue: 'Hypertrophy: 12-20 reps. Slow negatives.'),
        ]),
      ],
    ),

    // ── ADVANCED · Classic Body Part Split ───────────────────────────────
    Program(
      id: 'arnold',
      name: 'Classic Split',
      daysPerWeek: '6 days/week',
      experience: 'Advanced',
      description:
          'The classic high-volume body part split: chest & back, '
          'shoulders & arms, legs — twice a week. Big workload; for '
          'experienced lifters with recovery to match. Based on the '
          'Arnold Split.',
      source: 'Arnold Split — Arnold Schwarzenegger, '
          'The New Encyclopedia of Modern Bodybuilding',
      days: [
        ProgramDay(title: 'Chest & Back', exercises: [
          ProgramExercise(
              name: 'Bench press', sets: 4, reps: 8, startKg: 40,
              incrementKg: 2.5,
              cue: 'Controlled reps, full range.'),
          ProgramExercise(
              name: 'Incline dumbbell press', sets: 4, reps: 10, startKg: 16,
              incrementKg: 2,
              cue: 'Deep stretch at the bottom.'),
          ProgramExercise(
              name: 'Barbell row', sets: 4, reps: 8, startKg: 40,
              incrementKg: 2.5,
              cue: 'Strict hinge, squeeze the back.'),
          ProgramExercise(
              name: 'Lat pulldown', sets: 4, reps: 10, startKg: 35,
              incrementKg: 2.5,
              cue: 'Wide grip, chest to the bar path.'),
          ProgramExercise(
              name: 'Dumbbell pullover', sets: 3, reps: 12, startKg: 14,
              incrementKg: 2,
              cue: 'Big stretch, ribs down.'),
        ]),
        ProgramDay(title: 'Shoulders & Arms', exercises: [
          ProgramExercise(
              name: 'Overhead press', sets: 4, reps: 8, startKg: 25,
              incrementKg: 2.5,
              cue: 'Strict — no leg drive.'),
          ProgramExercise(
              name: 'Lateral raise', sets: 4, reps: 12, startKg: 8,
              incrementKg: 2,
              cue: 'Lead with the elbows.'),
          ProgramExercise(
              name: 'Biceps curl', sets: 4, reps: 10, startKg: 12,
              incrementKg: 2,
              cue: 'Full supination, squeeze.'),
          ProgramExercise(
              name: 'Triceps pushdown', sets: 4, reps: 10, startKg: 25,
              incrementKg: 2.5,
              cue: 'Elbows pinned, hard lockout.'),
          ProgramExercise(
              name: 'Face pull', sets: 3, reps: 15, startKg: 15,
              incrementKg: 2,
              cue: 'Rear delts — high elbows.'),
        ]),
        ProgramDay(title: 'Legs', exercises: [
          ProgramExercise(
              name: 'Squat', sets: 5, reps: 8, startKg: 50, incrementKg: 2.5,
              cue: 'Full depth, steady tempo.'),
          ProgramExercise(
              name: 'Romanian deadlift', sets: 4, reps: 10, startKg: 50,
              incrementKg: 2.5,
              cue: 'Hips back, flat back.'),
          ProgramExercise(
              name: 'Leg press', sets: 4, reps: 12, startKg: 100,
              incrementKg: 5,
              cue: 'Deep, controlled reps.'),
          ProgramExercise(
              name: 'Leg curl', sets: 3, reps: 12, startKg: 30,
              incrementKg: 2.5,
              cue: 'Squeeze, slow return.'),
          ProgramExercise(
              name: 'Standing calf raise', sets: 5, reps: 12, startKg: 50,
              incrementKg: 5,
              cue: 'Pause top and bottom.'),
        ]),
      ],
    ),
  ];
}
