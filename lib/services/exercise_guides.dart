library;

import '../models/exercise.dart';
import 'custom_exercises_service.dart';
import 'exercise_guides_data.dart';

class ExerciseGuides {
  ExerciseGuides._();

  static const attribution =
      'Illustrations: Free Exercise DB (public domain) — '
      'github.com/yuhonas/free-exercise-db';

  // Merge order: bulk database first, then the hand-curated guides (which
  // win on name collisions), then the user's custom exercises (which win
  // over everything — a user edit always takes priority).
  static final Map<String, Exercise> _combined = {
    ...freeExerciseDbGuides,
    ..._guides,
  };

  static Future<void> init() async {
    final custom = await CustomExercisesService.load();
    _combined.clear();
    _combined.addAll(freeExerciseDbGuides);
    _combined.addAll(_guides);
    for (final e in custom) {
      _combined[e.name] = e;
    }
  }

  static Exercise? byName(String name) => _combined[name];

  static List<Exercise> getAll() => _combined.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  /// Main muscle group per exercise — used to show how program days are
  /// split at a glance.
  static const muscles = <String, String>{
    'Squat': 'Legs',
    'Bench press': 'Chest',
    'Barbell row': 'Back',
    'Overhead press': 'Shoulders',
    'Deadlift': 'Back',
    'Lat pulldown': 'Back',
    'Dumbbell row': 'Back',
    'Face pull': 'Shoulders',
    'Triceps pushdown': 'Arms',
    'Biceps curl': 'Arms',
    'Lateral raise': 'Shoulders',
    'Incline dumbbell press': 'Chest',
    'Romanian deadlift': 'Legs',
    'Leg press': 'Legs',
    'Leg curl': 'Legs',
    'Standing calf raise': 'Legs',
    'Seated calf raise': 'Legs',
    'Walking lunge': 'Legs',
    'Dumbbell pullover': 'Chest',
    'Pull-up': 'Back',
    'Chin-up': 'Back',
    'Front squat': 'Legs',
    'Leg extension': 'Legs',
    'Seated leg press': 'Legs',
    'Close-grip bench press': 'Arms',
    'Cable row': 'Back',
    'Push-up': 'Chest',
    'Ab wheel': 'Core',
    'Dips': 'Arms',
    'Plank': 'Core',
    'Arnold press': 'Shoulders',
    'Hammer curl': 'Arms',
    'Skullcrushers': 'Arms',
    'Bulgarian split squat': 'Legs',
    'Glute bridge': 'Legs',
    'Goblet squat': 'Legs',
    'Lat pulldown (neutral grip)': 'Back',
    'Incline bench press': 'Chest',
    'Dumbbell bench press': 'Chest',
    'Dumbbell lateral raise': 'Shoulders',
    'Seated cable row': 'Back',
    'Preacher curl': 'Arms',
    'Concentration curl': 'Arms',
    'Overhead dumbbell extension': 'Arms',
    'Triceps dip': 'Arms',
    'Leg press (wide)': 'Legs',
    'Sumo deadlift': 'Back',
    'Hyperextension': 'Back',
  };

  /// Distinct main muscle groups for a set of exercise names, in order.
  static List<String> muscleGroupsFor(Iterable<String> exerciseNames) {
    final seen = <String>[];
    for (final n in exerciseNames) {
      final m = muscles[n] ?? 'Other';
      if (!seen.contains(m)) seen.add(m);
    }
    return seen;
  }

  static const _guides = <String, Exercise>{
    'Squat': Exercise(
      name: 'Squat',
      muscleGroup: 'Legs',
      imageIds: ['Barbell_Squat', 'Barbell_Full_Squat'],
      steps: [
        'Bar on your upper back, feet shoulder-width, toes slightly out.',
        'Brace your core, break at hips and knees together.',
        'Sit down until your hip crease is below your knee.',
        'Drive up through mid-foot, knees tracking over toes.',
      ],
    ),
    'Front squat': Exercise(
      name: 'Front squat',
      muscleGroup: 'Legs',
      imageIds: ['Barbell_Front_Squat'],
      steps: [
        'Bar on your front delts, elbows high, upright torso.',
        'Break at the hips and knees, keeping elbows up.',
        'Sit down until thighs are below parallel.',
        'Drive up through mid-foot, maintaining the shelf.',
      ],
    ),
    'Bench press': Exercise(
      name: 'Bench press',
      muscleGroup: 'Chest',
      imageIds: ['Barbell_Bench_Press_-_Medium_Grip'],
      steps: [
        'Lie with eyes under the bar, shoulder blades pinched, feet planted.',
        'Grip just outside shoulder width, unrack with straight arms.',
        'Lower the bar to mid-chest with elbows ~75° from your body.',
        'Press up and slightly back toward the rack, lock out.',
      ],
    ),
    'Close-grip bench press': Exercise(
      name: 'Close-grip bench press',
      muscleGroup: 'Arms',
      imageIds: ['Barbell_Close-Grip_Bench_Press'],
      steps: [
        'Lie on the bench, grip narrower than shoulder width.',
        'Lower the bar to mid-chest, keeping elbows tucked.',
        'Press up to full lockout using your triceps.',
      ],
    ),
    'Barbell row': Exercise(
      name: 'Barbell row',
      muscleGroup: 'Back',
      imageIds: ['Bent_Over_Barbell_Row'],
      steps: [
        'Hinge at the hips to ~45°, flat back, bar hanging at arms length.',
        'Pull the bar to your lower chest, elbows close.',
        'Squeeze the shoulder blades together at the top.',
        'Lower under control — no jerking or torso swing.',
      ],
    ),
    'Cable row': Exercise(
      name: 'Cable row',
      muscleGroup: 'Back',
      imageIds: ['Seated_Cable_Rows'],
      steps: [
        'Sit with feet braced, slight bend in knees.',
        'Pull the handle to your lower stomach.',
        'Squeeze your shoulder blades, keep back flat.',
        'Return to full stretch under control.',
      ],
    ),
    'Overhead press': Exercise(
      name: 'Overhead press',
      muscleGroup: 'Shoulders',
      imageIds: ['Standing_Military_Press', 'Barbell_Shoulder_Press'],
      steps: [
        'Grip just outside shoulders, bar on front delts, elbows forward.',
        'Squeeze glutes and brace — no leaning back.',
        'Press straight up, moving your head back slightly.',
        'Lock out overhead with the bar over mid-foot; head through.',
      ],
    ),
    'Deadlift': Exercise(
      name: 'Deadlift',
      muscleGroup: 'Back',
      imageIds: ['Barbell_Deadlift'],
      steps: [
        'Bar over mid-foot, shins close, grip just outside legs.',
        'Flat back, chest up, take the slack out of the bar.',
        'Push the floor away — hips and shoulders rise together.',
        'Stand tall, then lower along the same path.',
      ],
    ),
    'Lat pulldown': Exercise(
      name: 'Lat pulldown',
      muscleGroup: 'Back',
      imageIds: ['Wide-Grip_Lat_Pulldown', 'Full_Range-Of-Motion_Lat_Pulldown'],
      steps: [
        'Grip wide, chest up, slight lean back.',
        'Pull the bar to your upper chest, elbows down and back.',
        'Pause briefly with shoulder blades squeezed.',
        'Return under control to a full stretch.',
      ],
    ),
    'Pull-up': Exercise(
      name: 'Pull-up',
      muscleGroup: 'Back',
      imageIds: ['Pullups'],
      steps: [
        'Grip overhead bar wider than shoulders, palms away.',
        'Pull yourself up until your chin is over the bar.',
        'Squeeze your lats, then lower under control.',
      ],
    ),
    'Chin-up': Exercise(
      name: 'Chin-up',
      muscleGroup: 'Back',
      imageIds: ['Chinups'],
      steps: [
        'Grip overhead bar shoulder-width, palms facing you.',
        'Pull yourself up until your chin is over the bar.',
        'Squeeze your biceps and lats, lower under control.',
      ],
    ),
    'Dumbbell row': Exercise(
      name: 'Dumbbell row',
      muscleGroup: 'Back',
      imageIds: ['One-Arm_Dumbbell_Row'],
      steps: [
        'One knee and hand on a bench, flat back.',
        'Pull the dumbbell to your hip, elbow close to the body.',
        'Squeeze the lat at the top.',
        'Lower slowly to a full stretch.',
      ],
    ),
    'Face pull': Exercise(
      name: 'Face pull',
      muscleGroup: 'Shoulders',
      imageIds: ['Face_Pull'],
      steps: [
        'Rope at face height, step back for tension.',
        'Pull toward your eyebrows, elbows high and wide.',
        'Squeeze the rear delts, pause briefly.',
        'Return under control.',
      ],
    ),
    'Triceps pushdown': Exercise(
      name: 'Triceps pushdown',
      muscleGroup: 'Arms',
      imageIds: ['Triceps_Pushdown', 'Triceps_Pushdown_-_Rope_Attachment'],
      steps: [
        'Elbows pinned to your sides, forearms up.',
        'Push down to full lockout.',
        'Squeeze the triceps at the bottom.',
        'Let the weight back slowly without moving the elbows.',
      ],
    ),
    'Biceps curl': Exercise(
      name: 'Biceps curl',
      muscleGroup: 'Arms',
      imageIds: ['Barbell_Curl', 'Dumbbell_Bicep_Curl'],
      steps: [
        'Stand tall, elbows at your sides.',
        'Curl up without swinging the torso.',
        'Squeeze at the top.',
        'Lower slowly — control the negative.',
      ],
    ),
    'Lateral raise': Exercise(
      name: 'Lateral raise',
      muscleGroup: 'Shoulders',
      imageIds: ['Side_Lateral_Raise'],
      steps: [
        'Dumbbells at your sides, slight elbow bend.',
        'Raise out to shoulder height, leading with the elbows.',
        'Pause briefly at the top.',
        'Lower under control — no swinging.',
      ],
    ),
    'Incline dumbbell press': Exercise(
      name: 'Incline dumbbell press',
      muscleGroup: 'Chest',
      imageIds: ['Incline_Dumbbell_Press'],
      steps: [
        'Bench at 30–45°, dumbbells at chest level.',
        'Press up and slightly together.',
        'Lock out without clanging the weights.',
        'Lower to a full stretch with elbows ~45° from the body.',
      ],
    ),
    'Romanian deadlift': Exercise(
      name: 'Romanian deadlift',
      muscleGroup: 'Legs',
      imageIds: ['Romanian_Deadlift', 'Stiff-Legged_Barbell_Deadlift'],
      steps: [
        'Stand tall with the bar, soft knees.',
        'Push your hips straight back, bar sliding down the thighs.',
        'Stop when you feel a deep hamstring stretch — back stays flat.',
        'Drive the hips forward to stand tall.',
      ],
    ),
    'Leg press': Exercise(
      name: 'Leg press',
      muscleGroup: 'Legs',
      imageIds: ['Leg_Press'],
      steps: [
        'Feet shoulder-width on the platform.',
        'Lower until knees are ~90° — lower back stays on the pad.',
        'Press through mid-foot without locking the knees hard.',
      ],
    ),
    'Seated leg press': Exercise(
      name: 'Seated leg press',
      muscleGroup: 'Legs',
      imageIds: ['Seated_Leg_Press'],
      steps: [
        'Sit with your back against the pad, feet on the platform.',
        'Push the platform away until legs are extended.',
        'Lower under control without locking the knees.',
      ],
    ),
    'Leg extension': Exercise(
      name: 'Leg extension',
      muscleGroup: 'Legs',
      imageIds: ['Leg_Extensions'],
      steps: [
        'Sit with your back against the pad, shins behind the rollers.',
        'Extend your legs until straight.',
        'Squeeze your quads, then lower slowly.',
      ],
    ),
    'Leg curl': Exercise(
      name: 'Leg curl',
      muscleGroup: 'Legs',
      imageIds: ['Seated_Leg_Curl', 'Lying_Leg_Curls'],
      steps: [
        'Adjust the machine so your knee lines up with the pivot.',
        'Curl the pad toward you, squeezing the hamstring.',
        'Pause briefly, return slowly.',
      ],
    ),
    'Standing calf raise': Exercise(
      name: 'Standing calf raise',
      muscleGroup: 'Legs',
      imageIds: ['Standing_Calf_Raises'],
      steps: [
        'Balls of your feet on the edge, heels hanging.',
        'Rise as high as possible, pause at the top.',
        'Lower to a full stretch, pause — no bouncing.',
      ],
    ),
    'Seated calf raise': Exercise(
      name: 'Seated calf raise',
      muscleGroup: 'Legs',
      imageIds: ['Seated_Calf_Raise'],
      steps: [
        'Pads on your knees, balls of feet on the platform.',
        'Rise up, pause at the top.',
        'Lower slowly to a deep stretch.',
      ],
    ),
    'Walking lunge': Exercise(
      name: 'Walking lunge',
      muscleGroup: 'Legs',
      imageIds: ['Dumbbell_Lunges', 'Bodyweight_Walking_Lunge'],
      steps: [
        'Long step forward, torso upright.',
        'Lower until the back knee nearly touches the floor.',
        'Front knee tracks over the toes.',
        'Push off and step through into the next lunge.',
      ],
    ),
    'Dumbbell pullover': Exercise(
      name: 'Dumbbell pullover',
      muscleGroup: 'Chest',
      imageIds: ['Bent-Arm_Dumbbell_Pullover', 'Straight-Arm_Dumbbell_Pullover'],
      steps: [
        'Upper back on a bench, dumbbell held over your chest.',
        'Lower the weight back over your head to a big stretch.',
        'Keep ribs down and core braced.',
        'Pull back over the chest using lats and chest.',
      ],
    ),
    'Push-up': Exercise(
      name: 'Push-up',
      muscleGroup: 'Chest',
      imageIds: ['Pushups'],
      steps: [
        'Hands slightly wider than shoulders, body in a straight line.',
        'Lower yourself until chest nearly touches the floor.',
        'Push back up to the starting position.',
      ],
    ),
    'Ab wheel': Exercise(
      name: 'Ab wheel',
      muscleGroup: 'Core',
      imageIds: ['Ab_Wheel_Rollout'],
      steps: [
        'Kneel on the floor, hold the ab wheel with both hands.',
        'Roll the wheel forward as far as you can without arching your back.',
        'Pull yourself back to the starting position.',
      ],
    ),
    'Dips': Exercise(
      name: 'Dips',
      muscleGroup: 'Arms',
      imageIds: ['Triceps_Dips', 'Chest_Dips'],
      steps: [
        'Support yourself on parallel bars with straight arms.',
        'Lower yourself by bending elbows until they reach 90 degrees.',
        'Push back up to the starting position.',
      ],
    ),
    'Plank': Exercise(
      name: 'Plank',
      muscleGroup: 'Core',
      imageIds: ['Plank'],
      steps: [
        'Hold a push-up position with elbows on the floor.',
        'Keep body in a straight line from head to heels.',
        'Hold for the target duration.',
      ],
    ),
    'Arnold press': Exercise(
      name: 'Arnold press',
      muscleGroup: 'Shoulders',
      imageIds: ['Arnold_Press'],
      steps: [
        'Sit with dumbbells in front of shoulders, palms facing you.',
        'Press up while rotating palms to face away from you.',
        'Lower back to start while rotating palms back in.',
      ],
    ),
    'Hammer curl': Exercise(
      name: 'Hammer curl',
      muscleGroup: 'Arms',
      imageIds: ['Dumbbell_Hammer_Curl'],
      steps: [
        'Hold dumbbells at sides, palms facing your torso.',
        'Curl weights up while keeping palms facing in.',
        'Squeeze at the top, then lower under control.',
      ],
    ),
    'Skullcrushers': Exercise(
      name: 'Skullcrushers',
      muscleGroup: 'Arms',
      imageIds: ['EZ-Bar_Skullcrusher'],
      steps: [
        'Lie on bench, hold EZ-bar or dumbbells over chest.',
        'Lower weight toward forehead by bending only at elbows.',
        'Press back up to straight arms.',
      ],
    ),
    'Bulgarian split squat': Exercise(
      name: 'Bulgarian split squat',
      muscleGroup: 'Legs',
      imageIds: ['Dumbbell_Bulgarian_Split_Squat'],
      steps: [
        'One foot forward, other foot elevated on bench behind you.',
        'Lower hips until front thigh is nearly parallel to floor.',
        'Drive back up through front heel.',
      ],
    ),
    'Glute bridge': Exercise(
      name: 'Glute bridge',
      muscleGroup: 'Legs',
      imageIds: ['Glute_Bridge'],
      steps: [
        'Lie on back, knees bent, feet flat on floor.',
        'Lift hips toward ceiling by squeezing glutes.',
        'Hold briefly at top, then lower back down.',
      ],
    ),
    'Goblet squat': Exercise(
      name: 'Goblet squat',
      muscleGroup: 'Legs',
      imageIds: ['Dumbbell_Goblet_Squat'],
      steps: [
        'Hold one dumbbell or kettlebell against chest.',
        'Squat down until elbows touch inside of knees.',
        'Drive back up to standing position.',
      ],
    ),
    'Hyperextension': Exercise(
      name: 'Hyperextension',
      muscleGroup: 'Back',
      imageIds: ['Back_Extension_on_45-degree_bench'],
      steps: [
        'Position yourself on bench, heels secured.',
        'Lower torso toward floor, then lift until in line with legs.',
        'Squeeze lower back at top, avoid over-arching.',
      ],
    ),
    'Sumo deadlift': Exercise(
      name: 'Sumo deadlift',
      muscleGroup: 'Back',
      imageIds: ['Barbell_Sumo_Deadlift'],
      steps: [
        'Wide stance, feet pointed out, hands inside knees.',
        'Flat back, chest up, pull bar close to shins.',
        'Drive through floor to stand upright.',
      ],
    ),
    'Preacher curl': Exercise(
      name: 'Preacher curl',
      muscleGroup: 'Arms',
      imageIds: ['EZ-Bar_Preacher_Curl'],
      steps: [
        'Arms resting on preacher bench, palms up.',
        'Curl bar toward shoulders, keeping upper arms on pad.',
        'Lower slowly to full extension.',
      ],
    ),
  };
}
