using Godot;
using System;

public partial class Flashlight_Gizmo : Node3D
{
	[Export] public SpotLight3D Projector { get; set; }

	[Export] public float FollowSpeed { get; set; } = 5.0f;

	[Export] public Color FlashlightColor { get; set; } = new Color(0.6f, 0.8f, 1.0f);
	[Export] public float FlashlightEnergyOn { get; set; } = 16.0f;
	[Export] public float FlashlightEnergyOff { get; set; } = 0.0f;
	[Export] public float FlashlightRange { get; set; } = 1005.0f;
	[Export] public float FlashlightAngle { get; set; } = 20.0f;

	[Export] public float RampTime { get; set; } = 0.35f;
	[Export] public int RampProfile { get; set; } = 2;

	[Export] public float FlickerIntensity { get; set; } = 0.22f;
	[Export] public float FlickerSpeed { get; set; } = 12.0f;

	[Export] public float WideAngle { get; set; } = 55.0f;
	[Export] public float WideRange { get; set; } = 600.0f;
	[Export] public float NarrowAngle { get; set; } = 20.0f;
	[Export] public float NarrowRange { get; set; } = 1005.0f;

	private bool _flashlightToggle = false;
	private Vector3 _smoothDir;
	private bool _wideMode = false;
	private float _flickerTime = 0.0f;

	// --- Оптимизация ---
	private Camera3D _camera;
	private Vector3 _rayOrigin;
	private Vector3 _rayDir;
	private Vector3 _target;
	private Vector3 _targetDir;

	private const float RayLength = 20.0f;
	private static readonly Vector3 Up = Vector3.Up;
	private static readonly float MaxAngle = Mathf.DegToRad(60.0f);

	public override void _Ready()
	{
		_camera = GetViewport().GetCamera3D();

		if (Projector == null)
		{
			GD.PrintErr("Flashlight_Gizmo: Projector is not assigned!");
			return;
		}

		Projector.LightColor = FlashlightColor;
		Projector.SpotRange = 0.0f;
		Projector.SpotAngle = FlashlightAngle;
		Projector.SpotAttenuation = 1.5f;
		Projector.LightEnergy = FlashlightEnergyOff;
		Projector.ShadowEnabled = false;

		_smoothDir = -Projector.GlobalTransform.Basis.Z;
	}

	// === Public API ===
	public void Toggle()
	{
		if (_flashlightToggle)
			FlashlightOff();
		else
			FlashlightOn();
	}

	public bool IsOn() => _flashlightToggle;

	public void ToggleMode()
	{
		_wideMode = !_wideMode;

		float targetAngle = _wideMode ? WideAngle : NarrowAngle;
		float targetRange = _wideMode ? WideRange : NarrowRange;

		var tween = CreateTween().SetTrans(Tween.TransitionType.Sine).SetEase(Tween.EaseType.InOut);
		tween.TweenProperty(Projector, "spot_angle", targetAngle, 0.3f);
		tween.TweenProperty(Projector, "spot_range", targetRange, 0.3f);
	}

	// === Flashlight ON ===
	public void FlashlightOn()
	{
		_flashlightToggle = true;

		Projector.ShadowEnabled = false;
		Projector.SpotRange = 0.0f;
		Projector.LightEnergy = 0.0f;

		var tweenRange = CreateTween().SetTrans(GetProfileTrans()).SetEase(Tween.EaseType.Out);
		tweenRange.TweenProperty(Projector, "spot_range", FlashlightRange, RampTime);

		var tweenEnergy = CreateTween().SetTrans(GetProfileTrans()).SetEase(Tween.EaseType.Out);
		tweenEnergy.TweenProperty(Projector, "light_energy", FlashlightEnergyOn, RampTime * 0.8f);

		var tweenShadow = CreateTween();
		tweenShadow.TweenInterval(RampTime * 0.6f);
		tweenShadow.Finished += () => Projector.ShadowEnabled = true;
	}

	// === Flashlight OFF ===
	public void FlashlightOff()
	{
		_flashlightToggle = false;

		var tweenEnergy = CreateTween().SetTrans(GetProfileTrans()).SetEase(Tween.EaseType.In);
		tweenEnergy.TweenProperty(Projector, "light_energy", FlashlightEnergyOff, RampTime * 0.5f);

		var tweenRange = CreateTween().SetTrans(GetProfileTrans()).SetEase(Tween.EaseType.In);
		tweenRange.TweenProperty(Projector, "spot_range", 0.0f, RampTime * 0.6f);

		var tweenShadow = CreateTween();
		tweenShadow.TweenInterval(RampTime * 0.6f);
		tweenShadow.Finished += () => Projector.ShadowEnabled = false;
	}

	public override void _Process(double delta)
	{
		if (_camera != null && Projector != null)
		{
			var mousePos = GetViewport().GetMousePosition();
			_rayOrigin = _camera.ProjectRayOrigin(mousePos);
			_rayDir = _camera.ProjectRayNormal(mousePos);

			_target = _rayOrigin + _rayDir * RayLength;
			_targetDir = (_target - Projector.GlobalPosition).Normalized();

			_smoothDir = _smoothDir.Slerp(_targetDir, (float)(FollowSpeed * delta));

			var parent3D = GetParent<Node3D>();
			var parentForward = -parent3D.GlobalTransform.Basis.Z;
			float dot = parentForward.Dot(_smoothDir);

			if (dot < Mathf.Cos(MaxAngle))
			{
				var axis = parentForward.Cross(_smoothDir).Normalized();
				var limitedDir = parentForward.Rotated(axis, MaxAngle);
				_smoothDir = limitedDir.Normalized();
			}

			var clampedBasis = Basis.LookingAt(_smoothDir, Up);
			Projector.GlobalTransform = new Transform3D(clampedBasis, Projector.GlobalTransform.Origin);
		}

		if (_flashlightToggle && Projector != null)
		{
			_flickerTime += (float)delta * FlickerSpeed;
			float noise = Mathf.Sin(_flickerTime) * 0.5f + 0.5f;
			float flicker = 1.0f - FlickerIntensity + noise * FlickerIntensity;
			Projector.LightEnergy = Mathf.Lerp(FlashlightEnergyOff, FlashlightEnergyOn, flicker);
		}
	}

	// === Ramp profiles ===
	private Tween.TransitionType GetProfileTrans()
	{
		return RampProfile switch
		{
			0 => Tween.TransitionType.Quad,
			1 => Tween.TransitionType.Back,
			2 => Tween.TransitionType.Sine,
			_ => Tween.TransitionType.Back,
		};
	}
}
